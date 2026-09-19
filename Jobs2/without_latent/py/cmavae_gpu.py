"""
cmavae_gpu.py — CMAVAE (Cheng, Guo, Liu 2022, WSDM)

Causal Mediation Analysis with Hidden Confounders, using a single latent Z that
deconfounds T, M, Y simultaneously (the original sequential-ignorability-with-
proxies setup).

This is a Pyro reimplementation that mirrors the DMAVAE codebase structure so
the same data loaders / runners can be used.
"""

import logging

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

import pyro
import pyro.distributions as dist
from pyro import poutine
from pyro.infer import SVI, Trace_ELBO
from pyro.infer.util import torch_item
from pyro.nn import PyroModule
from pyro.optim import ClippedAdam
from pyro.util import torch_isnan

logger = logging.getLogger(__name__)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


# ----- Network building blocks (identical to DMAVAE) -------------------------
class FullyConnected(nn.Sequential):
    def __init__(self, sizes, final_activation=None):
        layers = []
        for in_size, out_size in zip(sizes, sizes[1:]):
            layers.append(nn.Linear(in_size, out_size))
            layers.append(nn.ELU())
        layers.pop(-1)
        if final_activation is not None:
            layers.append(final_activation)
        super().__init__(*layers)

    def append(self, layer):
        assert isinstance(layer, nn.Module)
        self.add_module(str(len(self)), layer)


class DistributionNet(nn.Module):
    @staticmethod
    def get_class(dtype):
        for cls in DistributionNet.__subclasses__():
            if cls.__name__.lower() == dtype + "net":
                return cls
        raise ValueError("dtype not supported: {}".format(dtype))


class BernoulliNet(DistributionNet):
    def __init__(self, sizes):
        super().__init__()
        self.fc = FullyConnected(sizes + [1])

    def forward(self, x):
        logits = self.fc(x).squeeze(-1).clamp(min=-10, max=10)
        return logits,

    @staticmethod
    def make_dist(logits):
        return dist.Bernoulli(logits=logits)


class NormalNet(DistributionNet):
    def __init__(self, sizes):
        super().__init__()
        self.fc = FullyConnected(sizes + [2])

    def forward(self, x):
        loc_scale = self.fc(x)
        loc = loc_scale[..., 0].clamp(min=-1e6, max=1e6)
        scale = nn.functional.softplus(loc_scale[..., 1]).clamp(min=1e-3, max=1e6)
        return loc, scale

    @staticmethod
    def make_dist(loc, scale):
        return dist.Normal(loc, scale)


class DiagNormalNet(nn.Module):
    def __init__(self, sizes):
        assert len(sizes) >= 2
        self.dim = sizes[-1]
        super().__init__()
        self.fc = FullyConnected(sizes[:-1] + [self.dim * 2])

    def forward(self, x):
        loc_scale = self.fc(x)
        loc = loc_scale[..., :self.dim].clamp(min=-1e2, max=1e2)
        scale = nn.functional.softplus(
            loc_scale[..., self.dim:]).add(1e-3).clamp(max=1e2)
        return loc, scale


class PreWhitener(nn.Module):
    def __init__(self, data):
        super().__init__()
        with torch.no_grad():
            loc = data.mean(0)
            scale = data.std(0)
            scale[~(scale > 0)] = 1.0
            self.register_buffer("loc", loc)
            self.register_buffer("inv_scale", scale.reciprocal())

    def forward(self, data):
        return (data - self.loc) * self.inv_scale


# ----- CMAVAE guide (inference network) --------------------------------------
class Guide(PyroModule):
    """
    Single-latent encoder.

    Posterior q(Z | X, M, T, Y) — note this conditions on M, T, Y at training
    time. During effect estimation, we use auxiliary predictors q(T|X),
    q(M|T,X), q(Y|T,M,X) (Eq. 22-26 in the CMAVAE paper) to fill in M, T, Y
    when only X is available.
    """
    def __init__(self, config):
        self.latent_dim = config["latent_dim"]
        OutcomeNet = DistributionNet.get_class(config["outcome_dist"])
        super().__init__()

        # Auxiliary predictors used both in training (for the encoder input)
        # and at test time (so the encoder can run on X alone).
        self.t_nn = BernoulliNet(
            [config["feature_dim"]]
            + [config["hidden_dim"]] * (config["num_layers"] - 1)
        )

        self.m_nn = FullyConnected(
            [config["feature_dim"]]
            + [config["hidden_dim"]] * (config["num_layers"] - 1),
            final_activation=nn.ELU(),
        )
        self.m0_nn = OutcomeNet([config["hidden_dim"]])
        self.m1_nn = OutcomeNet([config["hidden_dim"]])

        self.y_nn = FullyConnected(
            [config["feature_dim"] + 1]   # X concat M
            + [config["hidden_dim"]] * (config["num_layers"] - 1),
            final_activation=nn.ELU(),
        )
        self.y0_nn = OutcomeNet([config["hidden_dim"]])
        self.y1_nn = OutcomeNet([config["hidden_dim"]])

        # Posterior over Z, conditioning on (X, M, T, Y)
        # Two separate branches for T=0 and T=1 (TARnet-style)
        self.z_nn_t0 = FullyConnected(
            [config["feature_dim"] + 2]   # X concat M concat Y
            + [config["hidden_dim"]] * (config["num_layers"] - 1),
            final_activation=nn.ELU(),
        )
        self.z0_loc_scale = DiagNormalNet(
            [config["hidden_dim"], config["latent_dim"]])

        self.z_nn_t1 = FullyConnected(
            [config["feature_dim"] + 2]
            + [config["hidden_dim"]] * (config["num_layers"] - 1),
            final_activation=nn.ELU(),
        )
        self.z1_loc_scale = DiagNormalNet(
            [config["hidden_dim"], config["latent_dim"]])

    def forward(self, x, m=None, t=None, y=None, size=None):
        if size is None:
            size = x.size(0)
        with pyro.plate("data", size, subsample=x):
            # Auxiliary predictions condition on X (and downstream)
            t = pyro.sample("t", self.t_dist(x), obs=t,
                            infer={"is_auxiliary": True})
            m = pyro.sample("m", self.m_dist(t, x), obs=m,
                            infer={"is_auxiliary": True})
            y = pyro.sample("y", self.y_dist(t, m, x), obs=y,
                            infer={"is_auxiliary": True})

            # Posterior over Z, conditioning on (X, M, T, Y)
            z = pyro.sample("z", self.z_dist(x, m, t, y))

    def t_dist(self, x):
        logits, = self.t_nn(x)
        return dist.Bernoulli(logits=logits)

    def m_dist(self, t, x):
        hidden = self.m_nn(x)
        params0 = self.m0_nn(hidden)
        params1 = self.m1_nn(hidden)
        t_bool = t.bool()
        params = [torch.where(t_bool, p1, p0)
                  for p0, p1 in zip(params0, params1)]
        return self.m0_nn.make_dist(*params)

    def y_dist(self, t, m, x):
        x_m = torch.cat([x, m.unsqueeze(-1)], dim=-1)
        hidden = self.y_nn(x_m)
        params0 = self.y0_nn(hidden)
        params1 = self.y1_nn(hidden)
        t_bool = t.bool()
        params = [torch.where(t_bool, p1, p0)
                  for p0, p1 in zip(params0, params1)]
        return self.y0_nn.make_dist(*params)

    def z_dist(self, x, m, t, y):
        x_m_y = torch.cat([x, m.unsqueeze(-1), y.unsqueeze(-1)], dim=-1)
        hidden0 = self.z_nn_t0(x_m_y)
        hidden1 = self.z_nn_t1(x_m_y)
        loc0, scale0 = self.z0_loc_scale(hidden0)
        loc1, scale1 = self.z1_loc_scale(hidden1)
        t_b = t.bool().unsqueeze(-1)
        loc   = torch.where(t_b, loc1, loc0)
        scale = torch.where(t_b, scale1, scale0)
        return dist.Normal(loc, scale).to_event(1)


# ----- ELBO loss (same as DMAVAE) --------------------------------------------
class TraceCausalEffect_ELBO(Trace_ELBO):
    def _differentiable_loss_particle(self, model_trace, guide_trace):
        blocked_names = [name for name, site in guide_trace.nodes.items()
                         if site["type"] == "sample" and site["is_observed"]]
        blocked_guide_trace = guide_trace.copy()
        for name in blocked_names:
            del blocked_guide_trace.nodes[name]
        loss, surrogate_loss = super()._differentiable_loss_particle(
            model_trace, blocked_guide_trace)

        for name in blocked_names:
            log_q = guide_trace.nodes[name]["log_prob_sum"]
            loss = loss - torch_item(log_q)
            surrogate_loss = surrogate_loss - log_q

        return loss, surrogate_loss

    @torch.no_grad()
    def loss(self, model, guide, *args, **kwargs):
        return torch_item(self.differentiable_loss(model, guide, *args, **kwargs))


# ----- CMAVAE generative model -----------------------------------------------
class Model(PyroModule):
    """
    Generative model from CMAVAE paper Eq. (10)-(15).

    Z ~ N(0, I)
    X | Z      ~ N
    T | Z      ~ Bern
    M | T, Z   ~ N (TARnet: two heads)
    Y | T, M, Z ~ N (TARnet: two heads on concat(Z, M))
    """
    def __init__(self, config):
        self.latent_dim = config["latent_dim"]
        super().__init__()

        OutcomeNet = DistributionNet.get_class(config["outcome_dist"])

        # X | Z
        self.x_nn = DiagNormalNet(
            [config["latent_dim"]]
            + [config["hidden_dim"]] * config["num_layers"]
            + [config["feature_dim"]]
        )

        # T | Z
        self.t_nn = BernoulliNet(
            [config["latent_dim"]]
            + [config["hidden_dim"]] * (config["num_layers"] - 1)
        )

        # M | T, Z  -- two heads
        self.m0_nn = OutcomeNet(
            [config["latent_dim"]] + [config["hidden_dim"]] * config["num_layers"]
        )
        self.m1_nn = OutcomeNet(
            [config["latent_dim"]] + [config["hidden_dim"]] * config["num_layers"]
        )

        # Y | T, M, Z  -- two heads on concat(Z, M)
        self.y0_nn = OutcomeNet(
            [config["latent_dim"] + 1] + [config["hidden_dim"]] * config["num_layers"]
        )
        self.y1_nn = OutcomeNet(
            [config["latent_dim"] + 1] + [config["hidden_dim"]] * config["num_layers"]
        )

    def forward(self, x, m=None, t=None, y=None, size=None):
        if size is None:
            size = x.size(0)
        with pyro.plate("data", size, subsample=x):
            z = pyro.sample("z", self.z_dist())
            t = pyro.sample("t", self.t_dist(z), obs=t)
            x = pyro.sample("x", self.x_dist(z), obs=x)
            m = pyro.sample("m", self.m_dist(t, z), obs=m)
            y = pyro.sample("y", self.y_dist(t, m, z), obs=y)
        return y

    def y_mean(self, x, m, t=None):
        with pyro.plate("data", x.size(0)):
            z = pyro.sample("z", self.z_dist())
            x = pyro.sample("x", self.x_dist(z), obs=x)
            t = pyro.sample("t", self.t_dist(z), obs=t)
            m = pyro.sample("m", self.m_dist(t, z), obs=m)
        return self.y_dist(t, m, z).mean

    def m_mean(self, x, t=None):
        with pyro.plate("data", x.size(0)):
            z = pyro.sample("z", self.z_dist())
            x = pyro.sample("x", self.x_dist(z), obs=x)
            t = pyro.sample("t", self.t_dist(z), obs=t)
        return self.m_dist(t, z).mean

    def z_dist(self):
        return dist.Normal(0, 1).expand([self.latent_dim]).to_event(1)

    def x_dist(self, z):
        loc, scale = self.x_nn(z)
        return dist.Normal(loc, scale).to_event(1)

    def t_dist(self, z):
        logits, = self.t_nn(z)
        return dist.Bernoulli(logits=logits)

    def m_dist(self, t, z):
        params0 = self.m0_nn(z)
        params1 = self.m1_nn(z)
        t_bool = t.bool()
        params = [torch.where(t_bool, p1, p0)
                  for p0, p1 in zip(params0, params1)]
        return self.m0_nn.make_dist(*params)

    def y_dist(self, t, m, z):
        z_m = torch.cat([z, m.unsqueeze(-1)], dim=-1)
        params0 = self.y0_nn(z_m)
        params1 = self.y1_nn(z_m)
        t_bool = t.bool()
        params = [torch.where(t_bool, p1, p0)
                  for p0, p1 in zip(params0, params1)]
        return self.y0_nn.make_dist(*params)


# ----- Top-level wrapper (matches DMA_VAE API) -------------------------------
class CMA_VAE(nn.Module):
    def __init__(self, feature_dim, outcome_dist="normal",
                 latent_dim=5, hidden_dim=100, num_layers=3, num_samples=100):
        config = dict(
            feature_dim=feature_dim,
            latent_dim=latent_dim,
            hidden_dim=hidden_dim,
            num_layers=num_layers,
            num_samples=num_samples,
            outcome_dist=outcome_dist,
        )
        self.feature_dim = feature_dim
        self.num_samples = num_samples

        super().__init__()
        self.model = Model(config)
        self.guide = Guide(config)
        self.to(device)

    def fit(self, x, m, t, y,
            num_epochs=100, batch_size=100,
            learning_rate=1e-4, learning_rate_decay=0.1,
            weight_decay=1e-3):

        assert x.dim() == 2 and x.size(-1) == self.feature_dim
        self.whiten = PreWhitener(x)

        dataset = TensorDataset(x, m, t, y)
        dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=False)
        logger.info("Training with %d minibatches per epoch", len(dataloader))
        num_steps = num_epochs * len(dataloader)

        optim = ClippedAdam({
            "lr": learning_rate,
            "weight_decay": weight_decay,
            "lrd": learning_rate_decay ** (1 / num_steps),
        })
        svi = SVI(self.model, self.guide, optim, TraceCausalEffect_ELBO())

        losses = []
        for epoch in range(num_epochs):
            for xb, mb, tb, yb in dataloader:
                xb = self.whiten(xb)
                loss = svi.step(xb, mb, tb, yb, size=len(dataset)) / len(dataset)
                assert not torch_isnan(loss)
                losses.append(loss)
            print("Epoch:", int(epoch))
        return losses

    @torch.no_grad()
    def effect_estimation(self, x, num_samples=None, batch_size=None):
        if num_samples is None:
            num_samples = self.num_samples
        if not torch._C._get_tracing_state():
            assert x.dim() == 2 and x.size(-1) == self.feature_dim

        dataloader = [x] if batch_size is None else DataLoader(x,
                                                                batch_size=batch_size)
        result_NDE = []
        result_NIEr = []
        result_NIE = []
        result_ATE = []
        for x in dataloader:
            x = self.whiten(x)
            with pyro.plate("num_particles", num_samples, dim=-2):
                with poutine.trace() as tr, poutine.block(hide=["m", "t", "y"]):
                    self.guide(x)
                with poutine.do(data=dict(t=torch.zeros(()))):
                    m0 = poutine.replay(self.model.m_mean, tr.trace)(x)
                with poutine.do(data=dict(t=torch.ones(()))):
                    m1 = poutine.replay(self.model.m_mean, tr.trace)(x)
                with poutine.do(data=dict(t=torch.zeros(()))):
                    y0_m0 = poutine.replay(self.model.y_mean, tr.trace)(x, m0)
                    y0_m1 = poutine.replay(self.model.y_mean, tr.trace)(x, m1)
                with poutine.do(data=dict(t=torch.ones(()))):
                    y1_m0 = poutine.replay(self.model.y_mean, tr.trace)(x, m0)
                    y1_m1 = poutine.replay(self.model.y_mean, tr.trace)(x, m1)
                NDE  = (y1_m0 - y0_m0).mean(0)
                NIEr = (y1_m1 - y1_m0).mean(0)
                NIE  = (y0_m1 - y0_m0).mean(0)
                ATE  = (y1_m1 - y0_m0).mean(0)
                result_NDE.append(NDE)
                result_NIEr.append(NIEr)
                result_NIE.append(NIE)
                result_ATE.append(ATE)
        # NOTE: return is now correctly placed OUTSIDE the dataloader loop
        return (torch.cat(result_NDE),
                torch.cat(result_NIEr),
                torch.cat(result_NIE),
                torch.cat(result_ATE))

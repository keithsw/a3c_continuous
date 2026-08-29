#!/usr/bin/env bash
#
# Idempotent development-environment setup for a3c_continuous.
#
# This project is legacy code (PyTorch 0.3/0.4-era, OpenAI Gym 0.9.x). It relies
# on APIs that no longer exist in modern releases:
#   - gym.configuration.undo_logger_setup
#   - the gym.Wrapper `_step`/`_reset` convention
#   - the BipedalWalker-v2 / BipedalWalkerHardcore-v2 environments
#   - torch.autograd.Variable(..., volatile=True)
#
# To run it unmodified we pin an old, mutually-compatible stack inside a
# dedicated Python 3.6 Conda environment named "a3c".
set -euo pipefail

CONDA_HOME="${CONDA_HOME:-$HOME/miniconda3}"
ENV_NAME="a3c"
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"

echo "==> [a3c setup] Ensuring Miniconda is installed at ${CONDA_HOME}"
if [ ! -x "${CONDA_HOME}/bin/conda" ]; then
    tmp_installer="$(mktemp --suffix=.sh)"
    curl -fsSL -o "${tmp_installer}" "${MINICONDA_URL}"
    bash "${tmp_installer}" -b -p "${CONDA_HOME}"
    rm -f "${tmp_installer}"
else
    echo "    Miniconda already present; skipping download."
fi

# shellcheck disable=SC1091
source "${CONDA_HOME}/etc/profile.d/conda.sh"

# Use conda-forge exclusively so no defaults-channel Terms of Service prompt blocks us.
conda config --set channel_priority strict >/dev/null 2>&1 || true

echo "==> [a3c setup] Ensuring Conda env '${ENV_NAME}' (Python 3.6 + swig) exists"
if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
    conda create -y -n "${ENV_NAME}" --override-channels -c conda-forge python=3.6 swig pip
else
    echo "    Conda env '${ENV_NAME}' already present."
fi

conda activate "${ENV_NAME}"

echo "==> [a3c setup] Installing pinned Python dependencies"
# Guard the (network-heavy) pip step so re-runs are fast once satisfied.
if ! python -c "import torch, gym, setproctitle, Box2D, numpy" >/dev/null 2>&1; then
    pip install --no-input \
        "numpy==1.16.6" \
        "setproctitle==1.2.3" \
        "gym==0.9.5" \
        "pyglet==1.3.2" \
        "box2d-py==2.3.5" \
        "https://download.pytorch.org/whl/cpu/torch-0.4.1-cp36-cp36m-linux_x86_64.whl"
else
    echo "    Python dependencies already satisfied."
fi

echo "==> [a3c setup] Enabling auto-activation of '${ENV_NAME}' for interactive shells"
BASHRC="${HOME}/.bashrc"
MARKER="# >>> a3c conda auto-activate >>>"
if [ -f "${BASHRC}" ] && grep -qF "${MARKER}" "${BASHRC}"; then
    echo "    Auto-activation block already present."
else
    {
        echo ""
        echo "${MARKER}"
        echo "source \"${CONDA_HOME}/etc/profile.d/conda.sh\""
        echo "conda activate ${ENV_NAME}"
        echo "# <<< a3c conda auto-activate <<<"
    } >> "${BASHRC}"
fi

echo "==> [a3c setup] Verifying installation"
python - <<'PY'
import torch, gym, numpy, Box2D, setproctitle
print("    python  :", __import__("sys").version.split()[0])
print("    torch   :", torch.__version__)
print("    gym     :", gym.__version__)
print("    numpy   :", numpy.__version__)
from gym.configuration import undo_logger_setup  # noqa: F401
import argparse, sys
sys.path.insert(0, ".")
try:
    from environment import create_env
    env = create_env("BipedalWalkerHardcore-v2", argparse.Namespace(stack_frames=4))
    ob = env.reset()
    print("    env ok  : BipedalWalkerHardcore-v2 obs stack", ob.shape)
except Exception as exc:  # pragma: no cover - only when run outside repo root
    print("    (env smoke check skipped:", exc, ")")
PY

echo "==> [a3c setup] Done. Activate with: conda activate ${ENV_NAME}"

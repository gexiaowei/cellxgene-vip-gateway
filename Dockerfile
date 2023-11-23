FROM debian:bullseye

# ref: https://github.com/jupyter/docker-stacks/blob/master/base-notebook/Dockerfile
RUN sed -i 's#http://deb.debian.org#http://mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list
# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
# - tini is installed as a helpful container entrypoint that reaps zombie
#   processes and such of the actual executable we want to start, see
#   https://github.com/krallin/tini#why-tini for details.
# - apt-get upgrade is run to patch known vulnerabilities in apt-get packages as
#   the ubuntu base image is rebuilt too seldom sometimes (less than once a month)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt-get install --yes --no-install-recommends \
    git cpio build-essential python3 python3-pip cmake libhdf5-dev cmake llvm npm nodejs jq \
    tini wget ca-certificates sudo locales fonts-liberation && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}"

# Install conda as jovyan and check the sha256 sum provided on the download site
WORKDIR /tmp

ARG PYTHON_VERSION="3.8.12"

# CONDA_MIRROR is a mirror prefix to speed up downloading
# For example, people from mainland China could set it as
# https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease
# ARG CONDA_MIRROR=https://github.com/conda-forge/miniforge/releases/latest/download
ARG CONDA_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease
# ---- Miniforge installer ----
# Check https://github.com/conda-forge/miniforge/releases
# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# We're using Mambaforge installer, possible options:
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
# Installation: conda, mamba, pip
RUN set -x && \
    # Miniforge installer
    miniforge_arch=$(uname -m) && \
    miniforge_installer="Mambaforge-Linux-${miniforge_arch}.sh" && \
    wget --quiet "${CONDA_MIRROR}/${miniforge_installer}" && \
    /bin/bash "${miniforge_installer}" -f -b -p "${CONDA_DIR}" && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [ ${PYTHON_VERSION} != "default" ]; then mamba install --quiet --yes python="${PYTHON_VERSION}"; fi && \
    mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    # Using conda to update all packages: https://github.com/mamba-org/mamba/issues/1092
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf "/home/${NB_USER}/.cache/yarn"


# install R dependencies
RUN mamba install --quiet --yes \
    'r-base' \
    'r-cairo' \
    'r-ragg' \
    'r-ggrastr' \
    'r-arrow' \
    'r-biocmanager' \
    'r-foreign' \
    'r-ggpubr' \
    'r-rmarkdown' \
    'r-seurat' \
    'r-tidyverse' \
    'r-viridis' \
    'r-ellipsis' \
    'r-processx' && \
    mamba clean --all -f -y

# :FIXME: mamba couldn't find fgsea dependency
RUN R -q -e 'require(BiocManager); if(!require(fgsea)) BiocManager::install("fgsea")'

WORKDIR /cellxgene_VIP

# install Python depdendencies
ADD requirements.txt /cellxgene_VIP/requirements.txt
RUN pip install -r /cellxgene_VIP/requirements.txt

#modifies cellxgene 
COPY cellxgene /cellxgene_VIP/cellxgene
COPY VIPInterface.py interface.html fgsea.R gsea complexHeatmap.R volcano.R Density2D.R bubbleMap.R violin.R volcano.R browserPlot.R complexHeatmap.R proteinatlas_protein_class.csv complex_vlnplot_multiple.R index_template.insert /cellxgene_VIP/
COPY config.sh update.VIPInterface.sh /cellxgene_VIP/
RUN bash config.sh

# install cellxgene Python dependencies if any
RUN pip install -r /cellxgene_VIP/cellxgene/server/requirements.txt

RUN R -q -e 'if(!require(ComplexHeatmap)) BiocManager::install("ComplexHeatmap")'

COPY cellxgene-gateway /cellxgene_VIP/cellxgene-gateway


RUN pip install -r /cellxgene_VIP/cellxgene-gateway/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

ENV CELLXGENE_LOCATION=/opt/conda/bin/cellxgene
ENV CELLXGENE_DATA=/data

CMD ["python", "/cellxgene_VIP/cellxgene-gateway/gateway.py"]

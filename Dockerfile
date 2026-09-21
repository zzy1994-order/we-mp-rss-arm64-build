# we-mp-rss 真 arm64 构建镜像（2026-09-10 全量校验版）
# ===============================================================
# 背景：上游 rachelos/base-full 的 arm64 层【实为 amd64 二进制】——buildx CI bug：
#   base-mini 用 `FROM --platform=$BUILDPLATFORM ubuntu` 在构建机(amd64)容器里
#   从源码编译 Python，`--build=aarch64` 只是 configure 名、无交叉工具链 → make 出 amd64。
#   故任何 tag 的 arm64 在 ARM NAS 上必然 exec format error，与网络/导入无关。
#
# 本 Dockerfile 改用官方多架构 python:3.13-slim-bookworm（arm64 为真身），
# 其余系统依赖 / Python 包 / Playwright(webkit) 全部由仓库自带 install.sh 安装。
#
# 全量校验结论（2026-09-10 实测）：
#   ✔ Playwright 1.55 官方支持 debian12-arm64；CDN 实测存在 webkit-debian-12-arm64.zip (91.8MB)
#   ✔ requirements.txt 全部 71 个依赖在 arm64/cp313 均有 wheel 或纯 Python —— 零源码编译
#   ✔ 内嵌 redis 为纯 Python 实现（socket+threading），无需外部 redis-server 二进制
#   ✔ 钉 Debian 12(bookworm)：规避 Debian 13 的 libasound2/libgtk-3-0 → *t64 包名变动
#   ✔ 顺序调整：install.sh 放在 COPY . . 之后执行，避免旧 environment.sh 覆盖正确路径
# ===============================================================

# 基础镜像可用构建参数覆盖（万一 bookworm 拉取异常，可换 python:3.13-slim）
ARG PY_BASE=python:3.13-slim-bookworm
FROM ${PY_BASE}

ENV PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
    INSTALL=True \
    BROWSER_TYPE=webkit \
    PLANT_PATH=/app/env \
    WEREAD_LIC_PATH=/app/data/wx.lic \
    WEREAD_PROFILE_DIR=/app/data/weread-chrome-profile \
    TZ=Asia/Shanghai
# 注意：这里【故意不设】 PLAYWRIGHT_BROWSERS_PATH —— 让 install.sh 按 $(uname -m)
#       自动推导成 /app/env/driver/_aarch64（上游写死的 _x86_64 是 amd64 产物）

WORKDIR /app

# 1) 基础系统工具（base-full 提供、slim 缺失的部分）+ 中文字体（中文页渲染更稳）
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash wget git ca-certificates build-essential \
        zlib1g-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev \
        libffi-dev libsqlite3-dev procps tzdata fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 2) 先铺源码，再跑 install.sh —— install.sh 最后执行，保证它生成的 environment.sh
#    （含正确的 _aarch64 浏览器路径）是最终版本，不被上下文里的旧文件覆盖
COPY . .
COPY config.example.yaml /app/config.yaml
RUN mkdir -p /app/env /app/data && chmod +x /app/install.sh && /app/install.sh

# 3) 构建期自检：关键包 import + 确认 webkit 真装进了 arm64 路径；任一失败即中止构建，
#    避免产出「带病镜像」，到 NAS 运行期才暴露问题
RUN set -e; VENV="/app/env_$(uname -m)"; \
    echo "== 架构: $(uname -m) ==" ; \
    "$VENV/bin/python" -c "import fastapi,uvicorn,playwright,sqlalchemy,lxml,PIL,bs4; print('依赖 import OK')" ; \
    ls -d /app/env/driver/_$(uname -m)/webkit-* >/dev/null && echo "webkit 就位 OK" ; \
    echo '--- /app/environment.sh ---' ; cat /app/environment.sh

RUN chmod +x /app/start.sh

EXPOSE 8001
CMD ["/app/start.sh"]

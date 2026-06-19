FROM python:3.11

# 安装 Node.js（满足 >=18）及必要工具
RUN apt-get update \
  && apt-get install -y --no-install-recommends nodejs npm \
  && rm -rf /var/lib/apt/lists/*

# 从 uv 官方镜像复制 uv
COPY --from=ghcr.io/astral-sh/uv:0.9.26 /uv /uvx /bin/

WORKDIR /app

# torch/sentence-transformers 体积较大，uv 默认 30s 下载超时不够
ENV UV_HTTP_TIMEOUT=300

# 先复制依赖描述文件以利用缓存
COPY package.json package-lock.json ./
COPY frontend/package.json frontend/package-lock.json ./frontend/
COPY backend/pyproject.toml backend/uv.lock ./backend/

# 安装依赖：Node + Python（主环境带 graphiti extra）
RUN npm ci \
  && npm ci --prefix frontend \
  && cd backend && uv sync --extra graphiti --frozen

# 复制项目源码
COPY . .

# 模拟独立环境（camel-oasis 与 graphiti-core 的 neo4j driver 版本冲突，需隔离）
# 先装 CPU-only 版 torch（本机无 GPU），避免 sentence-transformers 间接拉入几 GB 的 CUDA 依赖
RUN cd backend \
  && uv venv .venv-simulation --python 3.11 \
  && uv pip install --python .venv-simulation/bin/python \
       torch --index-url https://download.pytorch.org/whl/cpu \
  && uv pip install --python .venv-simulation/bin/python \
       camel-oasis==0.2.5 camel-ai==0.2.78 openai python-dotenv

# 避免 `uv run` 在容器启动时按裸依赖重新同步，把 graphiti extra 同步掉
ENV UV_NO_SYNC=1

EXPOSE 3000 5001

# 同时启动前后端（开发模式，与上游 MiroFish 保持一致）
CMD ["npm", "run", "dev"]

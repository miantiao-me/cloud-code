FROM nikolaik/python-nodejs:python3.12-nodejs22-bookworm

ENV NODE_ENV=production

ARG TIGRISFS_VERSION=1.2.1
ARG CLOUDFLARED_DEB_URL=https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb

# 安装系统依赖 + tigrisfs/cloudflared/opencode，并清理缓存
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      fuse \
      ca-certificates \
      curl; \
    \
    curl -fsSL "https://github.com/tigrisdata/tigrisfs/releases/download/v${TIGRISFS_VERSION}/tigrisfs_${TIGRISFS_VERSION}_linux_amd64.deb" -o /tmp/tigrisfs.deb; \
    dpkg -i /tmp/tigrisfs.deb; \
    rm -f /tmp/tigrisfs.deb; \
    \
    curl -fsSL "${CLOUDFLARED_DEB_URL}" -o /tmp/cloudflared.deb; \
    dpkg -i /tmp/cloudflared.deb; \
    rm -f /tmp/cloudflared.deb; \
    \
    curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; \
    mv /root/.opencode/bin/opencode /usr/local/bin/opencode; \
    \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# 复制预置内容
COPY workspace /opt/workspace-init

# 创建启动脚本
RUN install -m 755 /dev/stdin /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

MOUNT_POINT="/root/s3"
INIT_DIR="/opt/workspace-init"
WORKSPACE_DIR="$MOUNT_POINT/workspace"
XDG_DIR="$MOUNT_POINT/.opencode"

setup_workspace() {
    mkdir -p "$WORKSPACE_DIR"
    mkdir -p "$XDG_DIR"/{config,data,state}

    export XDG_CONFIG_HOME="$XDG_DIR/config"
    export XDG_DATA_HOME="$XDG_DIR/data"
    export XDG_STATE_HOME="$XDG_DIR/state"

    PROJECT_DIR="$WORKSPACE_DIR"
}

copy_init() {
    cp -r "$INIT_DIR"/* "$WORKSPACE_DIR/" 2>/dev/null || true
    cp -r "$INIT_DIR"/.[!.]* "$WORKSPACE_DIR/" 2>/dev/null || true
}

copy_init_if_empty() {
    if [ -z "$(ls -A "$WORKSPACE_DIR" 2>/dev/null)" ]; then
        echo "[INFO] 首次启动，复制预置内容..."
        copy_init
        echo "[OK] 预置内容复制完成"
    fi
}

reset_mountpoint_dir() {
    # 确保挂载点是一个干净目录（避免 mount 覆盖旧内容）
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    fi
    rm -rf "$MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
}

if [ -z "$S3_ENDPOINT" ] || [ -z "$S3_BUCKET" ] || [ -z "$S3_ACCESS_KEY_ID" ] || [ -z "$S3_SECRET_ACCESS_KEY" ]; then
    echo "[WARN] S3 配置不完整，使用本地目录模式"

    # 在本地也使用同一套路径结构
    reset_mountpoint_dir
    setup_workspace
    copy_init
else
    echo "[INFO] 挂载 S3: ${S3_BUCKET} -> ${MOUNT_POINT}"

    reset_mountpoint_dir

    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
    # 区域配置，默认 auto
    export AWS_REGION="${S3_REGION:-auto}"
    # 路径风格，默认 false (virtual-hosted-style)
    export AWS_S3_PATH_STYLE="${S3_PATH_STYLE:-false}"

    if [ -n "$S3_PREFIX" ]; then
        BUCKET_ARG="${S3_BUCKET}:${S3_PREFIX}"
    else
        BUCKET_ARG="${S3_BUCKET}"
    fi

    # 构造挂载选项
    MOUNT_OPTS=""
    if [ -n "$TIGRISFS_ARGS" ]; then
        MOUNT_OPTS="$MOUNT_OPTS $TIGRISFS_ARGS"
    fi

    /usr/bin/tigrisfs --endpoint "${S3_ENDPOINT}" $MOUNT_OPTS -f "$BUCKET_ARG" "$MOUNT_POINT" &
    sleep 3

    if ! mountpoint -q "$MOUNT_POINT"; then
        echo "[ERROR] S3 挂载失败"
        exit 1
    fi
    echo "[OK] S3 挂载成功"

    setup_workspace
    copy_init_if_empty
fi

cleanup() {
    echo "[INFO] 正在关闭..."
    if [ -n "$OPENCODE_PID" ]; then
        kill -TERM "$OPENCODE_PID" 2>/dev/null
        wait "$OPENCODE_PID" 2>/dev/null
    fi
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "[INFO] 启动 OpenCode..."
cd "$PROJECT_DIR"
opencode web --port 2633 --hostname 0.0.0.0 &
OPENCODE_PID=$!
wait $OPENCODE_PID
EOF

WORKDIR /root/s3/workspace
EXPOSE 2633

CMD ["/entrypoint.sh"]

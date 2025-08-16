# Tunnel Freedom

一个简化版的 **Cloudflare Tunnel 脚本工具**，用于快速将本地服务暴露到公网。  
无需手动配置复杂的 Cloudflare Zero Trust，只依赖系统已安装的 `cloudflared`。

## 功能特点

- **检测环境**：确认 `/usr/bin/cloudflared` 是否存在，否则提示安装方法。  
- **支持两种模式**：
  1. **临时运行模式**：前台运行，自动获取 `trycloudflare.com` 临时域名。  
  2. **后台服务模式**：安装 `systemd` 服务，持久运行，并自动获取公网访问域名。  
- **服务管理**：
  - 如果检测到已有旧服务，可选择卸载或仅更新穿透目标。  
  - 日志保存于 `/var/log/cloudflared.log`，便于排错。  

## 使用方法

```bash
# 给予脚本执行权限
chmod +x cf-tunnel.sh

# 运行脚本
./cf-tunnel.sh
```

执行后：
1. 选择运行模式（前台 / 后台）。  
2. 输入本地服务地址（如 `127.0.0.1:8080`）。  
3. 稍等片刻将显示公网可访问的临时域名（形如 `xxxx.trycloudflare.com`）。  

## 注意事项

- 需预先通过 apt 安装 cloudflared（脚本已给出安装命令）。  
- 后台模式需要 root 权限（写入 systemd 配置）。  
- 这是一个简化工具，仅面向开发与临时演示场景 **⚠️ 不建议用于生产环境**。  

## 许可证

MIT License
import re
import sys

config_path = "/etc/containerd/config.toml"
registry_ip = sys.argv[1]
registry_url = f"{registry_ip}:5050"

with open(config_path, "r") as f:
    content = f.read()

# Enable SystemdCgroup
content = re.sub(r"SystemdCgroup\s*=\s*false", "SystemdCgroup = true", content)

# Clean up any existing mirror config for this registry to avoid duplicates
content = re.sub(fr'\[plugins\."io\.containerd\.cri\.v1\.images"\.registry\.mirrors\."{re.escape(registry_url)}"\].*?(\n\n|(?=\[))', '', content, flags=re.DOTALL)
content = re.sub(fr'\[plugins\."io\.containerd\.cri\.v1\.images"\.registry\.configs\."{re.escape(registry_url)}"\.tls\].*?(\n\n|(?=\[))', '', content, flags=re.DOTALL)

# Find the end of the registry section or just append to the file
mirror_config = f"""
[plugins."io.containerd.cri.v1.images".registry.mirrors."{registry_url}"]
  endpoint = ["http://{registry_url}"]
[plugins."io.containerd.cri.v1.images".registry.configs."{registry_url}".tls]
  insecure_skip_verify = true
"""

# Check if the registry section exists
if '[plugins."io.containerd.cri.v1.images".registry]' in content or "[plugins.'io.containerd.cri.v1.images'.registry]" in content:
    # Append to the end of the file as additional config
    content += mirror_config
else:
    # This shouldn't happen with containerd config default, but just in case
    content += mirror_config

with open(config_path, "w") as f:
    f.write(content)

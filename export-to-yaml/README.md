### 📦 `export-to-yaml.sh`

A simple Bash script to export a Kubernetes or OpenShift resource to a clean YAML file by stripping out unnecessary metadata and status fields.

---

### ✨ Features

- Supports any single resource type (e.g. `secret`, `pvc`, `configmap`, etc.)
- Cleans up auto-generated fields like:
  - `.metadata.annotations`
  - `.metadata.managedFields`
  - `.status`
  - `.resourceVersion`, `.uid`, and more
- Output is minimal and reusable — ideal for GitOps, backups, or templating

---

### 🧰 Requirements

- `oc` CLI (or `kubectl`, if adapted)
- `yq` version **4.x** ([install instructions](https://github.com/mikefarah/yq#install))

---

### 🚀 Usage

```bash
./export-to-yaml.sh <resource> <name> > output.yaml
```

#### Example:

```bash
./export-to-yaml.sh secret my-app-secret > my-app-secret.yaml
```

This will fetch the resource and output a clean YAML version with only the essential data and metadata.

---

### 📂 Example Output

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secret
data:
  USERNAME: ...
  PASSWORD: ...
type: Opaque
```

---

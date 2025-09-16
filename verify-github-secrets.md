# GitHub Secrets Setup for AUR Deployment

## Required Secrets

You need to set these secrets in your GitHub repository settings:
https://github.com/patrickjaja/claude-desktop-archlinux/settings/secrets/actions

### 1. AUR_SSH_KEY
```bash
# Copy the content of your private key:
cat /home/patrickjaja/.ssh/aur_private_key
```
- Copy the ENTIRE output (including -----BEGIN and -----END lines)
- Paste it as the value for `AUR_SSH_KEY` secret

### 2. AUR_USERNAME
```
patrickjaja
```

### 3. AUR_EMAIL
```
patrickjajaa@gmail.com
```

## Verify Secrets are Set

In GitHub, you should see these 3 secrets listed:
- `AUR_SSH_KEY` (should show "Updated" timestamp)
- `AUR_USERNAME` (should show "Updated" timestamp)
- `AUR_EMAIL` (should show "Updated" timestamp)

## Testing

After setting the secrets, you can trigger the deployment by:

1. **Manual trigger with workflow_dispatch:**
   - Go to Actions tab
   - Select "Build and Release Claude Desktop"
   - Click "Run workflow"
   - Set "Deploy to AUR" to "true"
   - Click "Run workflow"

2. **Or push a tag with 'aur':**
   ```bash
   git tag v0.13.11-aur
   git push origin v0.13.11-aur
   ```

The workflow will now use your SSH key to authenticate with AUR successfully!
# Ansible Vault Setup Guide

This project uses Ansible Vault to encrypt sensitive information like API keys, passwords, and SSH keys.

## Files Structure

```
├── group_vars/
│   ├── oracle_hosts.yml           # Plain text variables (safe to commit)
│   └── oracle_hosts_vault.yml     # Encrypted secrets (safe to commit)
├── .vault_password.template        # Template for vault password
├── .vault_password                 # Your actual vault password (DO NOT COMMIT)
└── .gitignore                      # Excludes .vault_password from git
```

## Initial Setup

1. **Set your vault password:**
   ```bash
   cp .vault_password.template .vault_password
   nano .vault_password  # Replace with your secure password
   chmod 600 .vault_password
   ```

2. **Edit encrypted secrets:**
   ```bash
   ansible-vault edit group_vars/oracle_hosts_vault.yml
   ```

3. **Update your secrets in the vault file:**
   - `vault_tailscale_auth_key`: Your Tailscale auth key
   - `vault_borg_repository`: Your backup repository URL
   - `vault_borg_ssh_user`: Backup server username
   - `vault_borg_ssh_host`: Backup server hostname
   - `vault_borg_passphrase`: Secure passphrase for Borg encryption

## Usage

### Running playbooks
```bash
# Password is automatically read from .vault_password
ansible-playbook site.yml

# Or manually specify password
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file /path/to/password/file
```

### Managing vault files
```bash
# Edit encrypted file
ansible-vault edit group_vars/oracle_hosts_vault.yml

# View encrypted file
ansible-vault view group_vars/oracle_hosts_vault.yml

# Change vault password
ansible-vault rekey group_vars/oracle_hosts_vault.yml

# Decrypt file (temporarily)
ansible-vault decrypt group_vars/oracle_hosts_vault.yml

# Re-encrypt file
ansible-vault encrypt group_vars/oracle_hosts_vault.yml
```

### Adding new secrets
1. Edit the vault file: `ansible-vault edit group_vars/oracle_hosts_vault.yml`
2. Add new variable: `vault_new_secret: "secret_value"`
3. Reference in main config: `new_secret: "{{ vault_new_secret }}"`

## Security Best Practices

1. **Never commit `.vault_password`** - it's in .gitignore
2. **Use strong vault passwords** - consider using a password manager
3. **Rotate secrets regularly**
4. **Use different vault passwords** for different environments
5. **Backup your vault password** securely

## Troubleshooting

### "Vault password required" error
- Ensure `.vault_password` file exists and has correct password
- Check file permissions: `chmod 600 .vault_password`

### "Decryption failed" error
- Verify vault password is correct
- Check if file is actually encrypted: `file group_vars/oracle_hosts_vault.yml`

### Running without .vault_password file
```bash
ansible-playbook site.yml --ask-vault-pass
```
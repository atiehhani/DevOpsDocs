# OpenSSL PKI on Rocky Linux 9: Direct Root CA and Intermediate CA Architectures

This guide consolidates the setup, commands, configuration, certificate issuance, verification, deployment, and troubleshooting discussed for the Rocky Linux 9 environment. It includes both architectures:

1. **Direct-signing architecture:** the Root CA signs server certificates directly.
2. **Intermediate architecture:** the Root CA signs an Intermediate CA certificate; the Intermediate CA signs server certificates.

The examples use the environment and certificate identity below. Replace values where your deployment differs.

| Item | Example |
|---|---|
| OS | Rocky Linux 9.x |
| CA host | `192.168.227.141` |
| Example server/client | `172.29.192.7` |
| Server FQDN | `scf.parsian-bank.ir` |
| Additional DNS SANs | `scf`, `localhost` |
| Additional IP SAN | `127.0.0.1` |
| Country / State / Locality | `IR` / `Tehran` / `Tehran` |
| Organization / OU | `Caspian` / `USA` |
| Email | `usa@caspian.com` |
| Desired lifetime | About 10 years (3650 days) |
| OpenSSL system config | `/etc/pki/tls/openssl.cnf` |
| CA working tree | `/etc/pki/CA` |
| Preferred file extensions | `.key`, `.csr`, `.crt` |

> **Validity note:** `-days 3650` means 3650 days, approximately ten years; it is not guaranteed to equal ten calendar years. A leaf certificate must not expire after its issuing CA certificate. Long-lived certificates increase the impact of key compromise and may not be accepted by all clients or policies.

---

## 1. Important concepts

- **Private key (`.key`):** secret; never send it with the certificate.
- **CSR (`.csr`):** certificate signing request containing a public key and requested identity.
- **Certificate (`.crt`):** signed public certificate.
- **Root CA:** trust anchor. Its private key is the most sensitive key in the PKI.
- **Intermediate CA:** CA certificate signed by the Root CA. It signs leaf/server certificates.
- **SAN (Subject Alternative Name):** DNS names and IP addresses clients actually validate. Modern TLS clients generally rely on SAN rather than only the Common Name.
- **Certificate chain:** leaf certificate plus the intermediate certificate(s) needed to reach a trusted Root CA. The Root CA is normally installed as a trust anchor separately.

Do not use the same key for the Root CA, Intermediate CA, and server. Do not copy a CA private key to the application server.

## 2. Install OpenSSL and prepare the host

Run on the CA host (`192.168.227.141`):

```bash
sudo dnf install -y openssl
openssl version -a
```

Create the conventional CA directories:

```bash
sudo install -d -m 700 /etc/pki/CA/private
sudo install -d -m 755 /etc/pki/CA/{certs,crl,newcerts,csr}
sudo touch /etc/pki/CA/index.txt
sudo chmod 600 /etc/pki/CA/index.txt
echo 1000 | sudo tee /etc/pki/CA/serial
sudo chmod 644 /etc/pki/CA/serial
```

Check the system OpenSSL configuration and its CA section:

```bash
grep -nE '^\[ *CA_default *\]|^dir[[:space:]]*=|^database[[:space:]]*=|^private_key[[:space:]]*=|^certificate[[:space:]]*=|^serial[[:space:]]*=' /etc/pki/tls/openssl.cnf
```

The examples below use explicit, dedicated configuration files to make paths and certificate extensions clear. This avoids accidentally depending on a different active section in the system-wide `openssl.cnf`.

---

# Part A — Architecture 1: Root CA signs server certificates directly

## A1. Architecture

```text
Trusted Root CA
  └── signs directly
        └── Server certificate (scf.parsian-bank.ir)
```

This is simpler, but the Root CA private key must be used whenever a leaf certificate is issued. For a production PKI, keeping the Root CA offline and using an Intermediate CA is usually operationally safer.

## A2. Create the Root CA private key and certificate

Create a dedicated directory:

```bash
sudo install -d -m 700 /etc/pki/CA/private
cd /etc/pki/CA
```

Create an encrypted Root CA private key. OpenSSL prompts for a passphrase:

```bash
sudo openssl genpkey -algorithm RSA \
  -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:4096 \
  -out /etc/pki/CA/private/cakey.pem
sudo chmod 600 /etc/pki/CA/private/cakey.pem
```

Create the self-signed Root CA certificate (approximately 10 years):

```bash
sudo openssl req -x509 -new \
  -key /etc/pki/CA/private/cakey.pem \
  -sha256 -days 3650 \
  -out /etc/pki/CA/cacert.pem \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=Caspian/OU=USA/CN=Caspian Root CA/emailAddress=usa@caspian.com" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
sudo chmod 644 /etc/pki/CA/cacert.pem
```

Inspect it:

```bash
openssl x509 -in /etc/pki/CA/cacert.pem -noout -subject -issuer -dates
openssl x509 -in /etc/pki/CA/cacert.pem -noout -text
```

The Root CA is self-signed, so its subject and issuer should match.

## A3. Configure the CA database

Create `/etc/pki/CA/openssl-root.cnf`:

```ini
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /etc/pki/CA
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
certificate       = $dir/cacert.pem
private_key       = $dir/private/cakey.pem
default_md        = sha256
default_days      = 3650
policy            = policy_server
x509_extensions   = server_cert
copy_extensions   = none
unique_subject    = no

[ policy_server ]
countryName             = supplied
stateOrProvinceName     = supplied
localityName            = supplied
organizationName        = supplied
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ server_cert ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
```

Protect the configuration from unauthorized edits:

```bash
sudo chmod 600 /etc/pki/CA/openssl-root.cnf
```

`copy_extensions = none` is deliberate: the CA does not blindly copy requested extensions from a CSR. The signing command below supplies the approved SAN extension file explicitly.

## A4. Create the server certificate configuration

On the CA host, create `/etc/pki/CA/csr/scf.conf`:

```ini
[ req ]
prompt = no
distinguished_name = req_distinguished_name
req_extensions = req_ext
default_md = sha256

[ req_distinguished_name ]
C = IR
ST = Tehran
L = Tehran
O = Caspian
OU = USA
CN = scf.parsian-bank.ir
emailAddress = usa@caspian.com

[ req_ext ]
subjectAltName = @alt_names
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[ alt_names ]
DNS.1 = scf.parsian-bank.ir
DNS.2 = scf
DNS.3 = localhost
IP.1 = 172.29.192.7
IP.2 = 127.0.0.1
```

This preserves the requested single-file style with `[req]`, `[req_distinguished_name]`, `[req_ext]`, and `[alt_names]`. The `extendedKeyUsage = serverAuth` line is appropriate for a TLS server certificate. If the certificate is for a different purpose, adjust the usage deliberately.

## A5. Generate the server key and CSR

Prefer generating the server private key on the server itself, so it never has to travel from the CA host. On `172.29.192.7`:

```bash
sudo install -d -m 700 /etc/pki/tls/private
sudo install -d -m 755 /etc/pki/tls/certs
cd /etc/pki/tls/private

sudo openssl genpkey -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out scf.key
sudo chmod 600 scf.key
```

Copy `scf.conf` to the server securely, or create the same file there. Then generate the CSR:

```bash
openssl req -new \
  -key /etc/pki/tls/private/scf.key \
  -out /tmp/scf.csr \
  -config /path/to/scf.conf
```

Transfer **only** `/tmp/scf.csr` and the configuration to the CA host. Never transfer `scf.key`.

Inspect the CSR on the CA:

```bash
openssl req -in /etc/pki/CA/csr/scf.csr -noout -subject -text
```

If the CSR was transferred to a different location, adjust the path. Verify the requested DNS names and IP addresses before signing.

## A6. Sign the CSR with the Root CA

Place the approved CSR at `/etc/pki/CA/csr/scf.csr` and the SAN configuration at `/etc/pki/CA/csr/scf.conf`.

```bash
sudo openssl ca \
  -config /etc/pki/CA/openssl-root.cnf \
  -in /etc/pki/CA/csr/scf.csr \
  -out /etc/pki/CA/certs/scf.crt \
  -extfile /etc/pki/CA/csr/scf.conf \
  -extensions req_ext \
  -days 3650 \
  -notext
```

OpenSSL will prompt for the Root key passphrase and ask you to confirm the certificate details. Review the subject and SANs before answering `y`.

The `openssl ca` command updates the CA database (`index.txt`), serial number, and `newcerts` archive. This is preferable to `openssl x509 -req` when you want a maintained CA issuance database.

## A7. Verify the issued certificate

```bash
openssl x509 -in /etc/pki/CA/certs/scf.crt -noout -subject -issuer -dates
openssl x509 -in /etc/pki/CA/certs/scf.crt -noout -ext subjectAltName
openssl verify -CAfile /etc/pki/CA/cacert.pem /etc/pki/CA/certs/scf.crt
```

Expected verification result:

```text
/etc/pki/CA/certs/scf.crt: OK
```

Check that the certificate and private key match:

```bash
openssl x509 -in /etc/pki/CA/certs/scf.crt -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum
openssl pkey -in /etc/pki/tls/private/scf.key -pubout -outform DER | sha256sum
```

The two hashes must match. Run the second command on the server holding `scf.key`.

## A8. Install on the server

Copy the signed leaf certificate to the server:

```bash
sudo install -m 644 scf.crt /etc/pki/tls/certs/scf.crt
sudo install -m 644 cacert.pem /etc/pki/ca-trust/source/anchors/caspian-root-ca.crt
sudo update-ca-trust
```

The Root CA certificate (`cacert.pem`) is public and may be distributed. Do **not** copy `/etc/pki/CA/private/cakey.pem` to the server.

Configure the service to use:

- Certificate: `/etc/pki/tls/certs/scf.crt`
- Private key: `/etc/pki/tls/private/scf.key`

For a web server, configure the certificate and key in that server's TLS configuration, validate its configuration, and reload/restart the service. The exact directives depend on the service.

---

# Part B — Architecture 2: Root CA → Intermediate CA → server certificates

## B1. Architecture

```text
Offline / tightly protected Root CA
  └── signs Intermediate CA certificate
        └── Intermediate CA signs server certificates
```

The Root CA is used only to establish or renew the Intermediate CA. Routine leaf issuance happens with the Intermediate CA. Keep the Root CA private key offline or otherwise tightly controlled.

This example uses:
- Root CA directory: `/etc/pki/CA/root`
- Intermediate CA directory: `/etc/pki/CA/intermediate`
- Root validity: 3650 days
- Intermediate validity: 1825 days (about 5 years; choose a period that fits your policy)
- Leaf validity: 365 days in this example (adjust as required, but never beyond the Intermediate's remaining validity)

Using a shorter leaf validity is a common operational choice. If you specifically require 10-year server certificates, the Intermediate must have a longer remaining validity than the leaf certificates, and the overall PKI policy and client requirements must permit it. A leaf must not outlive its issuing Intermediate, and the Intermediate must not outlive the Root.

## B2. Create separate Root and Intermediate directory trees

On the CA host:

```bash
sudo install -d -m 700 /etc/pki/CA/root/private
sudo install -d -m 755 /etc/pki/CA/root/{certs,crl,newcerts,csr}
sudo install -d -m 700 /etc/pki/CA/intermediate/private
sudo install -d -m 755 /etc/pki/CA/intermediate/{certs,crl,newcerts,csr}

sudo touch /etc/pki/CA/root/index.txt
sudo touch /etc/pki/CA/intermediate/index.txt
echo 1000 | sudo tee /etc/pki/CA/root/serial
echo 1000 | sudo tee /etc/pki/CA/intermediate/serial
echo 1000 | sudo tee /etc/pki/CA/intermediate/crlnumber
sudo chmod 600 /etc/pki/CA/root/index.txt /etc/pki/CA/intermediate/index.txt
```

Keep the Root and Intermediate databases, keys, certificates, and serial files separate.

## B3. Create the Root CA

Generate an encrypted Root key:

```bash
sudo openssl genpkey -algorithm RSA -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:4096 \
  -out /etc/pki/CA/root/private/root.key
sudo chmod 600 /etc/pki/CA/root/private/root.key
```

Create the Root certificate:

```bash
sudo openssl req -x509 -new \
  -key /etc/pki/CA/root/private/root.key \
  -sha256 -days 3650 \
  -out /etc/pki/CA/root/certs/root.crt \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=Caspian/OU=USA/CN=Caspian Root CA/emailAddress=usa@caspian.com" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
sudo chmod 644 /etc/pki/CA/root/certs/root.crt
```

Create `/etc/pki/CA/root/openssl.cnf`:

```ini
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /etc/pki/CA/root
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
certificate       = $dir/certs/root.crt
private_key       = $dir/private/root.key
default_md        = sha256
default_days      = 1825
policy            = policy_ca
x509_extensions   = v3_intermediate_ca
copy_extensions   = none
unique_subject    = no

[ policy_ca ]
countryName             = supplied
stateOrProvinceName     = supplied
localityName            = supplied
organizationName        = supplied
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ v3_intermediate_ca ]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
```

The `pathlen:0` constraint means this Intermediate may issue end-entity certificates but must not issue another subordinate CA.

## B4. Create the Intermediate key and CSR

Generate the Intermediate CA key (encrypted):

```bash
sudo openssl genpkey -algorithm RSA -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:4096 \
  -out /etc/pki/CA/intermediate/private/intermediate.key
sudo chmod 600 /etc/pki/CA/intermediate/private/intermediate.key
```

Create a CSR:

```bash
sudo openssl req -new \
  -key /etc/pki/CA/intermediate/private/intermediate.key \
  -out /etc/pki/CA/intermediate/csr/intermediate.csr \
  -sha256 \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=Caspian/OU=USA/CN=Caspian Issuing CA"
```

Inspect it:

```bash
openssl req -in /etc/pki/CA/intermediate/csr/intermediate.csr -noout -subject -text
```

## B5. Sign the Intermediate CSR with the Root

Use the Root CA configuration to sign the Intermediate CSR:

```bash
sudo openssl ca \
  -config /etc/pki/CA/root/openssl.cnf \
  -in /etc/pki/CA/intermediate/csr/intermediate.csr \
  -out /etc/pki/CA/intermediate/certs/intermediate.crt \
  -extensions v3_intermediate_ca \
  -days 1825 \
  -notext
```

Confirm the certificate details at the prompt. Verify the Intermediate against the Root:

```bash
openssl verify -CAfile /etc/pki/CA/root/certs/root.crt \
  /etc/pki/CA/intermediate/certs/intermediate.crt
```

Expected:

```text
/etc/pki/CA/intermediate/certs/intermediate.crt: OK
```

Check CA constraints and validity:

```bash
openssl x509 -in /etc/pki/CA/intermediate/certs/intermediate.crt -noout -subject -issuer -dates
openssl x509 -in /etc/pki/CA/intermediate/certs/intermediate.crt -noout -ext basicConstraints -ext keyUsage
```

## B6. Configure the Intermediate CA

Create `/etc/pki/CA/intermediate/openssl.cnf`:

```ini
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /etc/pki/CA/intermediate
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
crlnumber         = $dir/crlnumber
certificate       = $dir/certs/intermediate.crt
private_key       = $dir/private/intermediate.key
default_md        = sha256
default_days      = 365
policy            = policy_server
x509_extensions   = server_cert
copy_extensions   = none
unique_subject    = no

[ policy_server ]
countryName             = supplied
stateOrProvinceName     = supplied
localityName            = supplied
organizationName        = supplied
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ server_cert ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
```

Protect the key and configuration:

```bash
sudo chmod 600 /etc/pki/CA/intermediate/openssl.cnf
sudo chmod 600 /etc/pki/CA/intermediate/private/intermediate.key
```

The Intermediate key should be protected at least as carefully as any other CA key. Ideally, keep it on a restricted issuing system and protect it with a strong passphrase or hardware-backed key storage.

## B7. Create the server CSR

Generate the server key on the server `172.29.192.7`, not on the CA:

```bash
sudo install -d -m 700 /etc/pki/tls/private
sudo install -d -m 755 /etc/pki/tls/certs

sudo openssl genpkey -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out /etc/pki/tls/private/scf.key
sudo chmod 600 /etc/pki/tls/private/scf.key
```

Use the same `/req` and SAN configuration shown in **A4**. Generate the CSR:

```bash
openssl req -new \
  -key /etc/pki/tls/private/scf.key \
  -out /tmp/scf.csr \
  -config /path/to/scf.conf
```

Transfer the CSR and approved SAN config to the Intermediate CA, for example:

- `/etc/pki/CA/intermediate/csr/scf.csr`
- `/etc/pki/CA/intermediate/csr/scf.conf`

Review the CSR and SANs before signing:

```bash
openssl req -in /etc/pki/CA/intermediate/csr/scf.csr -noout -subject -text
```

## B8. Issue the server certificate from the Intermediate

```bash
sudo openssl ca \
  -config /etc/pki/CA/intermediate/openssl.cnf \
  -in /etc/pki/CA/intermediate/csr/scf.csr \
  -out /etc/pki/CA/intermediate/certs/scf.crt \
  -extfile /etc/pki/CA/intermediate/csr/scf.conf \
  -extensions req_ext \
  -days 365 \
  -notext
```

If your policy explicitly requires 10-year server certificates, change `-days 365` only after confirming that the Intermediate certificate will remain valid for the entire requested period. Also ensure the Root remains valid beyond the Intermediate's validity. A 10-year leaf cannot be validly chained through a 5-year Intermediate.

## B9. Build and verify the chain

Create a chain file containing the Intermediate certificate. Usually the server sends the leaf plus Intermediate; the Root is distributed separately as a trusted root:

```bash
cat /etc/pki/CA/intermediate/certs/intermediate.crt \
  > /etc/pki/CA/intermediate/certs/chain.crt
```

Verify the leaf using the Root as trust anchor and the Intermediate as an untrusted chain certificate:

```bash
openssl verify \
  -CAfile /etc/pki/CA/root/certs/root.crt \
  -untrusted /etc/pki/CA/intermediate/certs/intermediate.crt \
  /etc/pki/CA/intermediate/certs/scf.crt
```

Expected:

```text
/etc/pki/CA/intermediate/certs/scf.crt: OK
```

Check SANs and issuer:

```bash
openssl x509 -in /etc/pki/CA/intermediate/certs/scf.crt -noout -subject -issuer -dates
openssl x509 -in /etc/pki/CA/intermediate/certs/scf.crt -noout -ext subjectAltName
```

Create the server chain file (leaf first, then Intermediate):

```bash
cat /etc/pki/CA/intermediate/certs/scf.crt \
    /etc/pki/CA/intermediate/certs/intermediate.crt \
    > /etc/pki/CA/intermediate/certs/scf-fullchain.crt
```

Deploy `scf-fullchain.crt` and `scf.key` to the server. Install the Root certificate separately into the client's trust store. Do not normally include the Root certificate in the server's full-chain file.

## B10. Renew or revoke certificates

`openssl ca` maintains a database that supports tracking issued certificates and revocation. Keep backups of the CA database and serial files, and protect them from modification.

Inspect issued certificates:

```bash
sudo cat /etc/pki/CA/intermediate/index.txt
sudo ls -l /etc/pki/CA/intermediate/newcerts/
```

Revoke a leaf certificate (example):

```bash
sudo openssl ca \
  -config /etc/pki/CA/intermediate/openssl.cnf \
  -revoke /etc/pki/CA/intermediate/certs/scf.crt
```

Generating and publishing a CRL requires additional CRL configuration and a distribution method appropriate to your clients. Do not assume that revocation is checked automatically by every TLS client.

---

# Part C — Troubleshooting from the setup

## C1. `Problem with index file ... (could not load/parse file)`

Check the file:

```bash
ls -l /etc/pki/CA/index.txt
wc -c /etc/pki/CA/index.txt
cat -A /etc/pki/CA/index.txt
```

An empty CA database is valid. If the CA is brand new and has never issued certificates, a one-byte file containing only a newline may be the problem. For a **new CA with no issuance history**, reset it to zero bytes:

```bash
sudo truncate -s 0 /etc/pki/CA/index.txt
sudo chmod 600 /etc/pki/CA/index.txt
```

**Do not truncate an existing CA database.** It contains issuance and revocation records. Back up and investigate before modifying an established CA. Apply the same principle to the Root or Intermediate database path actually configured in the relevant `openssl.cnf`.

Optional setting to allow repeated subjects in the CA database:

```ini
unique_subject = no
```

This belongs in the relevant `[ CA_default ]` section. It does not repair a malformed database file.

## C2. OpenSSL looks for `/etc/pki/CA/private/cakey.pem`

That path comes from the active CA configuration. Inspect it:

```bash
grep -nE '^\[ *CA_default *\]|^dir[[:space:]]*=|^private_key[[:space:]]*=|^certificate[[:space:]]*=' /etc/pki/tls/openssl.cnf
```

If using a dedicated config, always pass it explicitly:

```bash
openssl ca -config /etc/pki/CA/openssl-root.cnf ...
```

For the Intermediate, use:

```bash
openssl ca -config /etc/pki/CA/intermediate/openssl.cnf ...
```

Do not mix a Root CA key/database with an Intermediate CA configuration.

## C3. `ansible`/shell says file is not writable or permission denied

CA private directories should be owned and writable only by the CA administrator/root. Use `sudo` for privileged commands and verify ownership and modes:

```bash
sudo ls -ld /etc/pki/CA /etc/pki/CA/private
sudo ls -l /etc/pki/CA/private
```

Do not solve permission errors by making private keys world-readable or making the entire CA tree writable by all users.

## C4. CSR has no SAN, or SAN is wrong

Inspect the CSR:

```bash
openssl req -in scf.csr -noout -text
```

Confirm the `X509v3 Subject Alternative Name` section contains the intended DNS names and IP addresses. The CSR config must include:

```ini
[ req ]
req_extensions = req_ext

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = scf.parsian-bank.ir
DNS.2 = scf
DNS.3 = localhost
IP.1 = 172.29.192.7
IP.2 = 127.0.0.1
```

Then sign using the intended extension section and file:

```bash
openssl ca ... -extfile scf.conf -extensions req_ext
```

A CSR's requested extensions are not automatically guaranteed to appear in the issued certificate. Inspect the issued certificate itself:

```bash
openssl x509 -in scf.crt -noout -ext subjectAltName
```

## C5. `openssl x509 -req` versus `openssl ca`

`openssl x509 -req` can sign a CSR, but it does not maintain the OpenSSL CA database in the same way as `openssl ca`. For a CA workflow where you need issuance records, serial management, and revocation tracking, use `openssl ca`.

## C6. Certificate verifies on the CA but fails on the server

Check:
1. The correct Root CA certificate is installed in the client/server trust store.
2. In the Intermediate architecture, the server presents the leaf and Intermediate chain.
3. The requested hostname/IP is present in the leaf SAN.
4. The certificate is within its validity period.
5. The service is using the intended certificate and matching private key.
6. The server's clock is correct.

For a TLS test, if the service supports TLS on port 443:

```bash
openssl s_client \
  -connect scf.parsian-bank.ir:443 \
  -servername scf.parsian-bank.ir \
  -showcerts \
  -verify_return_error
```

Use the actual service hostname and port. To test a private CA explicitly, add `-CAfile /path/to/root.crt`.

---

# Part D — Operational security and maintenance

1. **Protect CA keys.** Use a strong, unique passphrase. Never use a shared/default password.
2. **Keep the Root key offline** when using an Intermediate architecture. Bring it online only for controlled signing/maintenance.
3. **Back up CA state securely:** private keys, certificates, `index.txt`, `serial`, `crlnumber`, and configuration. Encrypt backups and restrict access.
4. **Do not lose the CA database.** It records issued/revoked certificates and must be preserved.
5. **Never distribute CA private keys.** Only public CA certificates are distributed to trust stores.
6. **Issue only approved SANs.** Verify every CSR and requested name/IP before signing.
7. **Keep certificate lifetimes coherent.** Leaf expiry must not exceed the issuing CA's expiry; Intermediate expiry must not exceed Root expiry.
8. **Use separate keys** for Root, Intermediate, and each server.
9. **Plan renewal and revocation** before production deployment.
10. **Check local policy and client compatibility.** A ten-year leaf may be rejected by some security policies or environments even if OpenSSL can issue it.

If a CA private-key passphrase or key has been exposed, treat it as compromised and follow a key-rotation/re-issuance plan. Changing only the passphrase does not undo a copy of the old private key.

---

# Quick reference: which files go where?

## Direct Root-signing architecture

**On the CA host:**
- `/etc/pki/CA/private/cakey.pem` — Root private key; secret
- `/etc/pki/CA/cacert.pem` — Root certificate; public
- `/etc/pki/CA/openssl-root.cnf` — CA configuration
- `/etc/pki/CA/index.txt`, `/etc/pki/CA/serial` — CA state
- `/etc/pki/CA/certs/scf.crt` — issued server certificate
- `/etc/pki/CA/csr/scf.csr` — incoming CSR

**On the server:**
- `/etc/pki/tls/private/scf.key` — server private key; secret
- `/etc/pki/tls/certs/scf.crt` — server certificate
- Root CA certificate in the trust store

## Intermediate architecture

**Root CA (restricted/offline):**
- `/etc/pki/CA/root/private/root.key` — Root private key; secret
- `/etc/pki/CA/root/certs/root.crt` — Root certificate; public
- `/etc/pki/CA/root/openssl.cnf`, `index.txt`, `serial` — Root configuration/state

**Intermediate CA (issuing CA):**
- `/etc/pki/CA/intermediate/private/intermediate.key` — Intermediate private key; secret
- `/etc/pki/CA/intermediate/certs/intermediate.crt` — Intermediate certificate
- `/etc/pki/CA/intermediate/openssl.cnf`, `index.txt`, `serial`, `crlnumber` — Intermediate configuration/state
- `/etc/pki/CA/intermediate/certs/scf.crt` — issued leaf certificate
- `/etc/pki/CA/intermediate/certs/scf-fullchain.crt` — leaf + Intermediate chain

**On the server:**
- `/etc/pki/tls/private/scf.key` — server private key; secret
- `/etc/pki/tls/certs/scf-fullchain.crt` — leaf plus Intermediate
- Root CA certificate installed in the trust store

---

## Final checklist

- [ ] Root CA key is protected and backed up securely.
- [ ] Root CA certificate has `CA:TRUE` and `keyCertSign,cRLSign`.
- [ ] Intermediate (if used) has `CA:TRUE,pathlen:0`.
- [ ] Server certificate has `CA:FALSE`, `serverAuth`, and correct SANs.
- [ ] CSR subject and SANs were reviewed before signing.
- [ ] Certificate and private key match.
- [ ] Direct architecture verifies against Root; Intermediate architecture verifies through Intermediate to Root.
- [ ] The server presents the correct chain.
- [ ] CA database and serial files are preserved.
- [ ] No CA private key was copied to the server.

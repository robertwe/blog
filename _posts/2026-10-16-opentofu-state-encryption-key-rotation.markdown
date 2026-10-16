---
layout: post
title: 'OpenTofu state encryption: encrypt an existing state and rotate the key without downtime'
date: 2026-10-16 12:00:00.00 +02:00
tag: ["DevOps", "OpenTofu", "Terraform", "IaC", "Security", "AWS"]
category: DevOps
---

Your state file has your database password in it. Not a hash, not a reference, the password. Also every secret the
AWS provider ever returned, every private key you generated with the `tls` provider, every `random_password`. S3
bucket encryption does not help here, because anyone who can read the bucket gets the plaintext back from S3. OpenTofu
1.7 added client-side state encryption: the state is encrypted before it leaves your machine and S3 only ever sees
ciphertext. This post is the practical part - turning it on for an existing project, and then rotating the key - because
the docs explain the blocks but not the sequence.
<!--more-->

## The three building blocks

Everything lives in a new `encryption` block inside `terraform {}`. Three kinds of things inside:

- a `key_provider` - where the key comes from (a passphrase, AWS KMS, GCP KMS, OpenBao),
- a `method` - how the key is used (`aes_gcm` is the one you want),
- and the targets - `state` and `plan`, each pointing at a method.

A minimal AWS setup looks like this:

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "main" {
      kms_key_id = "arn:aws:kms:eu-central-1:123456789012:key/0123abcd-..."
      region     = "eu-central-1"
      key_spec   = "AES_256"
    }

    method "aes_gcm" "main" {
      keys = key_provider.aws_kms.main
    }

    state {
      method = method.aes_gcm.main
    }

    plan {
      method = method.aes_gcm.main
    }
  }
}
```

On every write OpenTofu asks KMS for a fresh data key (`GenerateDataKey`), encrypts the state with it locally, and
stores the encrypted data key next to the ciphertext. On read it asks KMS to unwrap that data key. So the IAM
permission you need on the key is `kms:GenerateDataKey` and `kms:Decrypt`, nothing else. The key material never leaves
KMS, the plaintext state never leaves your process. Plan files get the same treatment, which matters more than people
think - a saved plan contains the full proposed state, secrets included.

If you do not have KMS, a passphrase works too:

```hcl
key_provider "pbkdf2" "main" {
  passphrase = var.state_passphrase   # at least 16 characters
}
```

Sensitive variable, fed from CI secrets. Fine for a personal project, not what I would pick for a team because now
you have a shared secret to rotate and no audit trail of who used it.

## Turning it on for a project that already has state

This is where people get stuck. You add the block above, run `tofu plan`, and it fails: OpenTofu tries to decrypt the
existing state, which is plaintext, and refuses. It will not silently guess.

The answer is a `fallback`. The `state` block can carry a second method that is only used for *reading*. Writing
always uses the primary method. So the migration is: primary = encrypted, fallback = unencrypted, apply once, remove
the fallback.

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "main" { ... }

    method "aes_gcm" "main" {
      keys = key_provider.aws_kms.main
    }

    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.main
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
```

Run `tofu apply` (an empty apply with no changes is enough, OpenTofu rewrites the state on every apply). Pull the state
with `tofu state pull` - if it worked you now see a JSON document with an `encrypted_data` field and base64 garbage
instead of your resources. Then delete the `unencrypted` method and the `fallback`, and add one more line:

```hcl
state {
  method   = method.aes_gcm.main
  enforced = true
}
```

`enforced = true` means "refuse to ever read or write unencrypted state". Without it, a colleague who checks out an old
commit without the encryption block can still accidentally write plaintext back. With it, OpenTofu errors out
instead. Turn it on as soon as the migration is done, and consider it part of the migration, not an optional extra.

## Rotating the key

Same trick, other direction. New key becomes primary, old key becomes fallback, apply, drop the fallback:

```hcl
key_provider "aws_kms" "old" {
  kms_key_id = "arn:aws:kms:eu-central-1:123456789012:key/0123abcd-..."
  region     = "eu-central-1"
  key_spec   = "AES_256"
}

key_provider "aws_kms" "new" {
  kms_key_id = "arn:aws:kms:eu-central-1:123456789012:key/4567ef01-..."
  region     = "eu-central-1"
  key_spec   = "AES_256"
}

method "aes_gcm" "old" { keys = key_provider.aws_kms.old }
method "aes_gcm" "new" { keys = key_provider.aws_kms.new }

state {
  method   = method.aes_gcm.new
  enforced = true
  fallback {
    method = method.aes_gcm.old
  }
}
```

One apply per state file, and the data is re-encrypted under the new key. Keep the old KMS key around until every
state that was ever encrypted with it has been rewritten - including the ones in that one workspace nobody has touched
since spring. Then schedule it for deletion. Note that with KMS you rarely *need* to rotate the customer master key
yourself, KMS can rotate the backing material automatically and old ciphertexts stay decryptable. The procedure above
is for when you actually want to move to a different key, say from a shared one to a per-project one.

## The bits that bite

**`terraform_remote_state` from another project.** If project B reads A's state with the `terraform_remote_state`
data source, B needs to be able to decrypt it. There is a dedicated block for that:

```hcl
encryption {
  remote_state_data_sources {
    default {
      method = method.aes_gcm.main
    }
  }
}
```

Forget it and B fails with a decryption error that mentions nothing about remote state.

**CI.** You probably do not want the key configuration duplicated in every root module. The whole `encryption`
block can be supplied through the `TF_ENCRYPTION` environment variable as HCL or JSON, and it is merged with what is
in the code. One variable in your CI secrets, no key ARNs scattered across repos.

**Terraform cannot read it anymore.** Obvious, but worth saying out loud: once the state is encrypted, `terraform`
and every tool that parses state directly (some policy scanners, some cost tools, your own `jq` scripts) sees only the
envelope. `tofu state pull` and `tofu show -json` still give you plaintext because they decrypt on the way out, so
pipe through those instead of reading the S3 object.

**Lock the config.** The encryption block is code, so a PR can remove `enforced = true`. Code review is the control
here; put the encryption config in a file that your `CODEOWNERS` routes to the platform team.

## Is it worth it

For a solo project with a private S3 bucket and no secrets in state - probably not, it is one more moving part. For
anything where several people and a CI system can read the bucket, I think it is the single cheapest security
improvement available in the whole toolchain: an afternoon, one KMS key, zero changes to the resources themselves,
and the "state file leaked" incident class is gone. It is also, as far as I can tell, the feature where OpenTofu is
furthest ahead of Terraform, which has had the "encrypt state at rest, client side" issue open since 2014.

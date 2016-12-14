# VaultUpdate

A tool to safely update Vault. Existing data is stored in history (which means rollbacks are supported). Diffs are printed. Individual keys can be updated at once.

# Installation

Install it yourself:

```
$ gem install vault-update
```

# Usage

First, ensure that the `VAULT_ADDR` and `VAULT_TOKEN` environment variables are set, then...

The basic summary:

```
$ vault-update --help
Safely update Vault secrets (with rollbacks and history!)

Usage:
       vault-update [options] -p SECRET_PATH KEY VALUE

Environment Variables:
    VAULT_ADDR (required)
    VAULT_TOKEN (required)

Options:
  -r, --rollback       Roll back to previous release
  -p, --path=<s>       Secret path to update
  -s, --history=<i>    Show the last N entries of history
  -l, --last           Show the last value
  -h, --help           Show this message
```

## Create a completely new key OR update a path without specifing a key separately

If valid JSON is specified on the command line (enclosed in single quotes), separate key and value arguments are not required. The JSON blob is merged "whole hog" with the existing value for the specified path.

```
$ vault-update -p secret/example '{"mykey": "myvalue"}'
Applying changes to secret/example:

-null
+{
+  "mykey": "myvalue"
+}
```

## Write a string value to a key

```
$ vault-update -p secret/example mykey myvalue
Applying changes to secret/example:

-null
+{
+  "mykey": "myvalue"
+}
```

## Roll the secret back to its previous value

```
$ vault-update -p secret/example -r
Writing to secret/example:
{"mykey":"myvalue"}
```


## Show the current contents of the secret

```
$ vault-update -p secret/example -c
{
  "mykey": "myvalue"
}
```

## Show the previous value (but do not roll back)

```
$ vault-update -p secret/example -l
{
  "mykey": "oldvalue"
}
```

## Show the last N history entries

```
$ vault-update -p secret/example -s 2
2016-10-26 17:14:56 -0400:
{
  "mykey": "reallyoldvalue"
}

2016-10-26 17:15:03 -0400:
{
  "mykey": "oldvalue"
}
```

# License

The gem is available as open source under the terms of the Apache license.

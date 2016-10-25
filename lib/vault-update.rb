require "vault-update/version"
require 'vault'
require 'trollop'
require 'json'

class VaultUpdate
  def update
    if opts[:rollback]
      rollback_secret
    else
      update_value = JSON.parse(ARGV.pop)
      update_key = ARGV.pop

      update_secret update_key, update_value
    end
  end

  private

  def rollback_secret
    raise 'There is no history for this key' unless (previous_secret = previous_update)
    update_secret previous_update
  end

  def update_secret(key, value)
    current_secret_value = vault_read opts[:path]
    secret_history = vault_read("#{opts[:path]}_history") || {}
    secret_history[Time.now.to_i] = current_secret_value
    vault_write "#{opts[:path]}_history", secret_history
    vault_write opts[:path], current_secret_value.merge(key => value)
  end

  def previous_update
    return nil unless (r = vault_read("#{opts[:path]}_history"))
    r[r.keys.sort.last] # Return the value with the highest key
  end

  def opts
    @opts ||= Trollop.options do
      opt :rollback, 'Roll back to previous release', short: 'r'
      opt :path, 'Secret path to update', short: 'p', required: true, type: String
    end
  end

  def vault_read(path)
    r = vault.with_retries(Vault::HTTPConnectionError) do |attempt, e|
      puts "Received exception #{e} from Vault - attempt #{attempt}"
      vault.logical.read(path)
    end
    r ? r.data : nil
  end

  def vault
    @vault ||= Vault::Client.new
  end
end

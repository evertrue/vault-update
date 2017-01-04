require 'vault-update/version'
require 'vault'
require 'trollop'
require 'json'
require 'diffy'
require 'colorize'
require 'facets'

class MissingInputError < StandardError; end
class NoHistoryError < StandardError; end
class NoUpdateError < StandardError; end
class NoValueError < StandardError; end

class VaultUpdate
  def run
    if opts[:history]
      secret_history.sort_by { |ts, _data| ts }[-history_fetch_size..-1].each do |ts, data|
        puts "#{Time.at(ts.to_s.to_i)}:".colorize(:green)
        puts JSON.pretty_generate(data) + "\n\n"
      end
    elsif opts[:last]
      puts JSON.pretty_generate(
        (secret_history.sort_by { |ts, _data| ts }.last || fail(NoHistoryError))[1]
      )
    elsif opts[:rollback]
      rollback_secret
    elsif opts[:current]
      puts JSON.pretty_generate(vault_read(opts[:path]) || fail(NoValueError))
    else
      update
    end
  rescue MissingInputError, TypeError => e
    raise e unless e.class == TypeError && e.message == 'no implicit conversion of nil into String'
    Trollop.die 'KEY and VALUE must be provided'
  rescue NoUpdateError
    puts 'Nothing to do'
    exit 0
  rescue NoHistoryError
    puts 'ERROR: '.colorize(:red) + "There is no history for #{opts[:path]}"
    exit 2
  rescue NoValueError
    puts 'ERROR: '.colorize(:red) + "There is no current value for #{opts[:path]}"
    exit 3
  end

  private

  def history_fetch_size
    opts[:history] > secret_history.keys.count ? secret_history.keys.count : opts[:history]
  end

  def update
    update_value = ARGV.pop

    json_value = true

    # JSON is optional in the value field, so we have this funny business
    update_value = (
      begin
        JSON.parse update_value
      rescue JSON::ParserError
        json_value = false
        update_value
      end
    )

    update_key = ARGV.pop

    raise(MissingInputError) unless json_value || update_key
    update_secret(json_value ? update_value : { update_key.to_sym => update_value })
  end

  def debug?
    ENV['DEBUG']
  end

  def rollback_secret
    fail NoHistoryError unless previous_update
    current_secret_value = vault_read opts[:path]

    # Update history with {} if empty now
    secret_history[Time.now.to_i] = (current_secret_value || {})
    vault_write "#{opts[:path]}_history", secret_history

    puts "Writing to #{opts[:path]}:\n".bold + JSON.pretty_generate(previous_update) unless debug?
    vault_write opts[:path], previous_update
  end

  def update_secret(update_hash)
    data =
      if (current_secret_value = vault_read(opts[:path]))
        current_secret_value = current_secret_value.stringify_keys
        merged_value = current_secret_value.merge update_hash.stringify_keys

        if debug?
          puts "current_secret_value: ".colorize(:blue) + current_secret_value.inspect
          puts "merged_value: ".colorize(:blue) + merged_value.inspect
        end

        fail NoUpdateError if current_secret_value == merged_value

        secret_history[Time.now.to_i] = current_secret_value
        vault_write "#{opts[:path]}_history", secret_history

        current_secret_value
      else
        puts "update_hash: ".colorize(:blue) + update_hash.inspect
        update_hash
      end

    puts "data: ".colorize(:blue) + data.inspect if debug?

    puts "Applying changes to #{opts[:path]}:\n".bold
    puts Diffy::Diff.new(
      JSON.pretty_generate(current_secret_value) + "\n", # What to do if no existing content
      JSON.pretty_generate(data) + "\n"
    ).to_s(:color)

    vault_write opts[:path], data
  end

  def previous_update
    @previous_update ||= begin
      return nil unless (r = secret_history).any?
      r[r.keys.sort.last] # Return the value with the highest key
    end
  end

  def secret_history
    @secret_history ||= begin
      r = vault_read("#{opts[:path]}_history")
      r ? r.dup : {}
    end
  end

  def opts
    @opts ||= begin
      opts = Trollop.options do
        version "vault-update #{VaultUpdate::VERSION} (c) 2017 Evertrue"
        banner(
          "Safely update Vault secrets (with rollbacks and history!)\n\n" \
          "Usage:\n" \
          "       vault-update [options] -p SECRET_PATH KEY VALUE\n" \
          "\nEnvironment Variables:\n" \
          "    VAULT_ADDR (required)\n" \
          "    VAULT_TOKEN (required)\n" \
          "\nOptions:"
        )
        opt :rollback, 'Roll back to previous release', short: 'r'
        opt :path, 'Secret path to update', short: 'p', required: true, type: String
        opt :history, 'Show the last N entries of history', short: 's', type: Integer
        opt :last, 'Show the last value', short: 'l'
        opt :current, 'Show the current contents of the secret', short: 'c'
      end

      fail 'VAULT_ADDR and VAULT_TOKEN must be set' unless ENV['VAULT_ADDR'] && ENV['VAULT_TOKEN']

      opts
    end
  end

  def vault_write(path, data)
    puts "Writing to #{path}:\n".colorize(:blue) + data.inspect if debug?
    vault.with_retries(Vault::HTTPConnectionError) do |attempt, e|
      puts "Received exception #{e} from Vault - attempt #{attempt}" if e
      vault.logical.write(path, data)
    end
  end

  def vault_read(path)
    r = vault.with_retries(Vault::HTTPConnectionError) do |attempt, e|
      puts "Received exception #{e} from Vault - attempt #{attempt}" if e
      vault.logical.read(path)
    end
    res = r ? r.data : nil
    puts "Read from #{path}:\n".colorize(:blue) + res.to_json if debug?
    res
  end

  def vault
    @vault ||= Vault::Client.new
  end
end

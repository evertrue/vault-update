require 'vault-update/version'
require 'vault'
require 'trollop'
require 'json'
require 'diffy'
require 'byebug'

class MissingInputError < StandardError; end
class NoHistoryError < StandardError; end
class NoUpdateError < StandardError; end

class VaultUpdate
  def run
    if opts[:history]
      secret_history.each do |ts, data|
        puts "#{Time.at(ts.to_s.to_i)}:"
        puts JSON.pretty_generate(data) + "\n\n"
      end
    elsif opts[:last]
      puts JSON.pretty_generate(secret_history.sort_by { |ts, _data| ts }[-opts[:history]..-1][1])
    else
      update
    end
  end

  private

  def update
    # byebug
    if opts[:rollback]
      rollback_secret
    else
      update_value = ARGV.pop
      update_value = (
        begin
          JSON.parse update_value
        rescue JSON::ParserError
          update_value
        end
      )

      update_key = ARGV.pop

      raise(MissingInputError) unless (update_key && update_value)

      update_secret update_key.to_sym => update_value
    end
  rescue MissingInputError, TypeError => e
    raise e unless e.class == TypeError && e.message == 'no implicit conversion of nil into String'
    Trollop.die 'KEY and VALUE must be provided'
  rescue NoUpdateError
    puts 'Nothing to do'
    exit 0
  rescue NoHistoryError
    puts "ERROR: There is no history for #{opts[:path]}"
    exit 2
  end

  def debug?
    ENV['DEBUG']
  end

  def rollback_secret
    raise NoHistoryError unless previous_update
    current_secret_value = vault_read opts[:path]

    # Update history with {} if empty now
    secret_history[Time.now.to_i] = (current_secret_value || {})
    vault_write "#{opts[:path]}_history", secret_history

    puts "Writing to #{opts[:path]}:\n#{previous_update.to_json}" unless debug?
    vault_write opts[:path], previous_update
  end

  def update_secret(update_hash)
    data =
      if (current_secret_value = vault_read opts[:path])
        secret_history[Time.now.to_i] = current_secret_value
        vault_write "#{opts[:path]}_history", secret_history
        current_secret_value.merge(update_hash)
      else
        update_hash
      end

    if debug?
      puts "current_secret_value: #{current_secret_value}"
      puts "update_hash: #{update_hash}"
    end

    raise NoUpdateError if current_secret_value == data

    puts "Applying changes to #{opts[:path]}:\n\n"
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
      end
      raise 'VAULT_ADDR and VAULT_TOKEN must be set' unless (ENV['VAULT_ADDR'] && ENV['VAULT_TOKEN'])
      opts
    end
  end

  def vault_write(path, data)
    puts "Writing to #{path}:\n#{data.inspect}" if debug?
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
    puts "Read from #{path}:\n#{res.to_json}" if debug?
    res
  end

  def vault
    @vault ||= Vault::Client.new
  end
end

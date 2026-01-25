# frozen_string_literal: true

module Search
  module Actions
    # Converts npub (bech32) to hex pubkey, or validates hex pubkey.
    # Supports: npub1..., hex (64 chars)
    class ConvertNpub < BaseService
      NPUB_PREFIX = "npub"
      HEX_PUBKEY_LENGTH = 64

      option :identifier, type: Types::String

      def call
        return Failure(:empty_identifier) if identifier.blank?

        hex = if npub?
                decode_npub
        elsif valid_hex?
                identifier.downcase
        end

        return Failure(:invalid_pubkey) unless hex

        Success(pubkey: hex)
      end

      private

      def npub?
        identifier.downcase.start_with?(NPUB_PREFIX)
      end

      def valid_hex?
        identifier.match?(/\A[0-9a-fA-F]{#{HEX_PUBKEY_LENGTH}}\z/)
      end

      def decode_npub
        hrp, data = Bech32.decode(identifier.downcase)
        return nil unless hrp == NPUB_PREFIX && data

        # Convert 5-bit groups to 8-bit bytes
        bytes = Bech32.convert_bits(data, 5, 8, false)
        return nil unless bytes&.length == 32

        bytes.pack("C*").unpack1("H*")
      rescue Bech32::Bech32Error
        nil
      end
    end
  end
end

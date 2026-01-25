# frozen_string_literal: true

require "digest"
require "nostr"

module Events
  module Actions
    class VerifySignature < BaseService
      option :event_data, type: Types::Hash

      def call
        # Normalize keys to strings (JSON.parse returns string keys)
        @data = event_data.transform_keys(&:to_s)

        # 1. Validate structure with dry-validation contract
        validation = NostrRelay::Contracts::EventContract.new.call(@data)
        return Failure[:invalid, "invalid: #{validation.errors.to_h}"] unless validation.success?

        # 2. Verify ID matches canonical JSON hash
        return Failure[:invalid, "invalid: event id does not match"] unless id_valid?

        # 3. Verify Schnorr signature (BIP-340)
        return Failure[:invalid, "invalid: bad signature"] unless signature_valid?

        Success(@data)
      end

      private

      def id_valid?
        computed_id = Digest::SHA256.hexdigest(canonical_json)
        computed_id == @data["id"]
      end

      def canonical_json
        # NIP-01: Canonical serialization for ID computation
        [
          0,
          @data["pubkey"],
          @data["created_at"],
          @data["kind"],
          @data["tags"],
          @data["content"]
        ].to_json
      end

      def signature_valid?
        # Use the nostr gem's crypto utilities for BIP-340 Schnorr verification
        crypto = Nostr::Crypto.new
        crypto.valid_sig?(
          @data["id"],
          Nostr::PublicKey.new(@data["pubkey"]),
          Nostr::Signature.new(@data["sig"])
        )
      rescue StandardError => e
        Rails.logger.error("Signature verification error: #{e.message}")
        false
      end
    end
  end
end

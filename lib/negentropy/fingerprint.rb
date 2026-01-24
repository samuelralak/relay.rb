# frozen_string_literal: true

require "digest"

module Negentropy
  # Computes fingerprints for set reconciliation
  # Fingerprint = first 16 bytes of SHA-256(sum_of_ids || varint(count))
  module Fingerprint
    SIZE = 16 # bytes
    ID_SIZE = 32 # bytes (256 bits)
    MODULO = 2**256

    module_function

    # Compute fingerprint from a list of event IDs
    # @param ids [Array<String>] array of 32-byte binary event IDs
    # @return [String] 16-byte binary fingerprint
    def compute(ids)
      return empty_fingerprint if ids.empty?

      # Sum all IDs as little-endian 256-bit integers mod 2^256
      sum = ids.reduce(0) { |acc, id|
        # Convert binary ID to little-endian integer
        id_int = id.unpack("C*").reverse.reduce(0) { |n, byte| (n << 8) | byte }
        (acc + id_int) % MODULO
      }

      # Convert sum back to 32-byte little-endian binary
      sum_bytes = []
      32.times do
        sum_bytes << (sum & 0xFF)
        sum >>= 8
      end
      sum_binary = sum_bytes.pack("C*")

      # Append count as varint
      data = sum_binary + Varint.encode(ids.length)

      # SHA-256 and take first 16 bytes
      Digest::SHA256.digest(data)[0, SIZE]
    end

    # Compute fingerprint from hex event IDs
    # @param hex_ids [Array<String>] array of 64-char hex event IDs
    # @return [String] 16-byte binary fingerprint
    def compute_from_hex(hex_ids)
      binary_ids = hex_ids.map { |hex| [ hex ].pack("H*") }
      compute(binary_ids)
    end

    # Get an empty fingerprint (for empty ranges)
    # @return [String] 16-byte zero fingerprint
    def empty_fingerprint
      "\x00".b * SIZE
    end

    # Check if a fingerprint is empty
    # @param fp [String] 16-byte binary fingerprint
    # @return [Boolean] true if fingerprint is all zeros
    def empty?(fingerprint)
      fingerprint == empty_fingerprint
    end

    # Compare two fingerprints for equality
    # @param fp1 [String] first fingerprint
    # @param fp2 [String] second fingerprint
    # @return [Boolean] true if fingerprints match
    def match?(fp1, fp2)
      fp1 == fp2
    end

    # XOR two fingerprints (for incremental computation)
    # @param fp1 [String] first fingerprint
    # @param fp2 [String] second fingerprint
    # @return [String] XOR result
    def xor(fp1, fp2)
      fp1.bytes.zip(fp2.bytes).map { |a, b| a ^ b }.pack("C*")
    end

    # Convert fingerprint to hex string for display
    # @param fingerprint [String] 16-byte binary fingerprint
    # @return [String] 32-char hex string
    def to_hex(fingerprint)
      fingerprint.unpack1("H*")
    end

    # Parse fingerprint from hex string
    # @param hex [String] 32-char hex string
    # @return [String] 16-byte binary fingerprint
    def from_hex(hex)
      [ hex ].pack("H*")
    end
  end
end

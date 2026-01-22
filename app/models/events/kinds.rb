# frozen_string_literal: true

module Events
  # Event kind constants and classification helpers per NIP-01
  # https://github.com/nostr-protocol/nips/blob/master/01.md
  module Kinds
    # Hex format validation pattern
    HEX_PATTERN = /\A[a-f0-9]+\z/

    # ===========================================
    # Kind Ranges (NIP-01)
    # ===========================================

    # Regular: stored, multiple events per pubkey allowed
    # 1000 <= n < 10000 || 4 <= n < 45 || n == 1 || n == 2
    REGULAR_RANGE_PRIMARY = (1000...10_000)
    REGULAR_RANGE_LEGACY = (4...45)
    REGULAR_STANDALONE = [ 1, 2 ].freeze

    # Replaceable: only latest per pubkey+kind stored
    # 10000 <= n < 20000 || n == 0 || n == 3
    REPLACEABLE_RANGE = (10_000...20_000)
    REPLACEABLE_STANDALONE = [ 0, 3 ].freeze

    # Ephemeral: not stored by relays
    # 20000 <= n < 30000
    EPHEMERAL_RANGE = (20_000...30_000)

    # Addressable (Parameterized Replaceable): only latest per pubkey+kind+d-tag stored
    # 30000 <= n < 40000
    ADDRESSABLE_RANGE = (30_000...40_000)

    # ===========================================
    # Core Protocol Kinds (NIP-01, NIP-02, NIP-09)
    # ===========================================
    METADATA = 0           # User metadata (NIP-01)
    TEXT_NOTE = 1          # Short text note (NIP-01, NIP-10)
    RECOMMEND_RELAY = 2    # Recommend relay (deprecated)
    FOLLOWS = 3            # Follow list (NIP-02)
    CONTACTS = 3           # Alias for FOLLOWS
    DELETION = 5           # Event deletion request (NIP-09)

    # ===========================================
    # Direct Messages (NIP-04, NIP-17)
    # ===========================================
    ENCRYPTED_DM = 4       # Encrypted DM (NIP-04, deprecated)
    SEAL = 13              # Seal (NIP-59)
    DIRECT_MESSAGE = 14    # Direct message (NIP-17)
    FILE_MESSAGE = 15      # File message (NIP-17)

    # ===========================================
    # Social Interactions (NIP-18, NIP-25)
    # ===========================================
    REPOST = 6             # Repost (NIP-18)
    REACTION = 7           # Reaction (NIP-25)
    BADGE_AWARD = 8        # Badge award (NIP-58)
    GENERIC_REPOST = 16    # Generic repost (NIP-18)
    WEBSITE_REACTION = 17  # Reaction to website (NIP-25)

    # ===========================================
    # Chat & Threads (NIP-28, NIP-7D, NIP-C7)
    # ===========================================
    CHAT_MESSAGE = 9       # Chat message (NIP-C7)
    THREAD = 11            # Thread (NIP-7D)

    # ===========================================
    # Media (NIP-68, NIP-71)
    # ===========================================
    PICTURE = 20           # Picture (NIP-68)
    VIDEO = 21             # Video event (NIP-71)
    SHORT_VIDEO = 22       # Short-form portrait video (NIP-71)
    PUBLIC_MESSAGE = 24    # Public message (NIP-A4)

    # ===========================================
    # Channels (NIP-28)
    # ===========================================
    CHANNEL_CREATE = 40    # Channel creation
    CHANNEL_METADATA = 41  # Channel metadata
    CHANNEL_MESSAGE = 42   # Channel message
    CHANNEL_HIDE = 43      # Channel hide message
    CHANNEL_MUTE = 44      # Channel mute user

    # ===========================================
    # Special Purpose
    # ===========================================
    VANISH_REQUEST = 62    # Request to vanish (NIP-62)
    CHESS = 64             # Chess PGN (NIP-64)

    # ===========================================
    # Regular Range (1000-9999)
    # ===========================================
    POLL_RESPONSE = 1018   # Poll response (NIP-88)
    BID = 1021             # Bid (NIP-15)
    BID_CONFIRMATION = 1022 # Bid confirmation (NIP-15)
    OPEN_TIMESTAMPS = 1040 # OpenTimestamps (NIP-03)
    GIFT_WRAP = 1059       # Gift wrap (NIP-59)
    FILE_METADATA = 1063   # File metadata (NIP-94)
    POLL = 1068            # Poll (NIP-88)
    COMMENT = 1111         # Comment (NIP-22)
    VOICE_MESSAGE = 1222   # Voice message (NIP-A0)
    LIVE_CHAT = 1311       # Live chat message (NIP-53)
    CODE_SNIPPET = 1337    # Code snippet (NIP-C0)
    REPORTING = 1984       # Reporting (NIP-56)
    LABEL = 1985           # Label (NIP-32)
    TORRENT = 2003         # Torrent (NIP-35)
    COMMUNITY_APPROVAL = 4550 # Community post approval (NIP-72)
    JOB_FEEDBACK = 7000    # Job feedback (NIP-90)
    ZAP_GOAL = 9041        # Zap goal (NIP-75)
    NUTZAP = 9321          # Nutzap (NIP-61)
    ZAP_REQUEST = 9734     # Zap request (NIP-57)
    ZAP = 9735             # Zap (NIP-57)
    HIGHLIGHTS = 9802      # Highlights (NIP-84)

    # Job request range (NIP-90)
    JOB_REQUEST_RANGE = (5000...6000)
    # Job result range (NIP-90)
    JOB_RESULT_RANGE = (6000...7000)
    # Group control events range (NIP-29)
    GROUP_CONTROL_RANGE = (9000..9030)

    # ===========================================
    # Replaceable Range (10000-19999)
    # ===========================================
    MUTE_LIST = 10_000     # Mute list (NIP-51)
    PIN_LIST = 10_001      # Pin list (NIP-51)
    RELAY_LIST = 10_002    # Relay list metadata (NIP-65)
    BOOKMARK_LIST = 10_003 # Bookmark list (NIP-51)
    COMMUNITIES_LIST = 10_004 # Communities list (NIP-51)
    PUBLIC_CHATS_LIST = 10_005 # Public chats list (NIP-51)
    BLOCKED_RELAYS = 10_006 # Blocked relays list (NIP-51)
    SEARCH_RELAYS = 10_007 # Search relays list (NIP-51)
    USER_GROUPS = 10_009   # User groups (NIP-51, NIP-29)
    INTERESTS_LIST = 10_015 # Interests list (NIP-51)
    USER_EMOJI_LIST = 10_030 # User emoji list (NIP-51)
    DM_RELAY_LIST = 10_050 # Relay list to receive DMs (NIP-17)
    FILE_SERVERS = 10_063  # User server list (Blossom)
    WALLET_INFO = 13_194   # Wallet info (NIP-47)

    # ===========================================
    # Ephemeral Range (20000-29999)
    # ===========================================
    AUTH = 22_242          # Client authentication (NIP-42)
    WALLET_REQUEST = 23_194 # Wallet request (NIP-47)
    WALLET_RESPONSE = 23_195 # Wallet response (NIP-47)
    NOSTR_CONNECT = 24_133 # Nostr connect (NIP-46)
    BLOSSOM_BLOB = 24_242  # Blobs on mediaservers (Blossom)
    HTTP_AUTH = 27_235     # HTTP auth (NIP-98)

    # ===========================================
    # Addressable Range (30000-39999)
    # ===========================================
    FOLLOW_SETS = 30_000   # Follow sets (NIP-51)
    RELAY_SETS = 30_002    # Relay sets (NIP-51)
    BOOKMARK_SETS = 30_003 # Bookmark sets (NIP-51)
    CURATION_SETS = 30_004 # Curation sets (NIP-51)
    VIDEO_SETS = 30_005    # Video sets (NIP-51)
    PICTURE_SETS = 30_006  # Picture sets (NIP-51)
    KIND_MUTE_SETS = 30_007 # Kind mute sets (NIP-51)
    PROFILE_BADGES = 30_008 # Profile badges (NIP-58)
    BADGE_DEFINITION = 30_009 # Badge definition (NIP-58)
    INTEREST_SETS = 30_015 # Interest sets (NIP-51)
    STALL = 30_017         # Marketplace stall (NIP-15)
    PRODUCT = 30_018       # Marketplace product (NIP-15)
    LONG_FORM = 30_023     # Long-form content (NIP-23)
    DRAFT_LONG_FORM = 30_024 # Draft long-form content (NIP-23)
    EMOJI_SETS = 30_030    # Emoji sets (NIP-51)
    APP_DATA = 30_078      # Application-specific data (NIP-78)
    RELAY_DISCOVERY = 30_166 # Relay discovery (NIP-66)
    LIVE_EVENT = 30_311    # Live event (NIP-53)
    USER_STATUS = 30_315   # User statuses (NIP-38)
    CLASSIFIED = 30_402    # Classified listing (NIP-99)
    REPO_ANNOUNCEMENT = 30_617 # Repository announcement (NIP-34)
    WIKI_ARTICLE = 30_818  # Wiki article (NIP-54)
    DRAFT_EVENT = 31_234   # Draft event (NIP-37)
    FEED = 31_890          # Feed (Custom feeds)
    CALENDAR_DATE = 31_922 # Date-based calendar event (NIP-52)
    CALENDAR_TIME = 31_923 # Time-based calendar event (NIP-52)
    CALENDAR = 31_924      # Calendar (NIP-52)
    CALENDAR_RSVP = 31_925 # Calendar event RSVP (NIP-52)
    HANDLER_REC = 31_989   # Handler recommendation (NIP-89)
    HANDLER_INFO = 31_990  # Handler information (NIP-89)
    ADDRESSABLE_VIDEO = 34_235 # Addressable video event (NIP-71)
    COMMUNITY_DEF = 34_550 # Community definition (NIP-72)
    GROUP_METADATA_RANGE = (39_000..39_009) # Group metadata (NIP-29)

    class << self
      # Check if a kind is regular (stored, multiple allowed)
      def regular?(kind)
        REGULAR_RANGE_PRIMARY.cover?(kind) ||
          REGULAR_RANGE_LEGACY.cover?(kind) ||
          REGULAR_STANDALONE.include?(kind)
      end

      # Check if a kind is replaceable (only latest per pubkey+kind)
      def replaceable?(kind)
        REPLACEABLE_RANGE.cover?(kind) ||
          REPLACEABLE_STANDALONE.include?(kind)
      end

      # Check if a kind is ephemeral (not stored)
      def ephemeral?(kind)
        EPHEMERAL_RANGE.cover?(kind)
      end

      # Check if a kind is addressable (only latest per pubkey+kind+d-tag)
      def addressable?(kind)
        ADDRESSABLE_RANGE.cover?(kind)
      end

      alias parameterized_replaceable? addressable?

      # Check if relay should store this kind
      def storable?(kind)
        !ephemeral?(kind)
      end

      # Get the classification of a kind
      def classification(kind)
        return :ephemeral if ephemeral?(kind)
        return :addressable if addressable?(kind)
        return :replaceable if replaceable?(kind)

        :regular
      end
    end
  end
end

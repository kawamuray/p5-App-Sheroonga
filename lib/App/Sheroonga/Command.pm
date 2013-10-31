package App::Sheroonga::Command;
use 5.008005;
use strict;
use warnings;

our %GroongaOptions = (
    table => sub {
        my ($shrng) = @_;

        my $res = $shrng->exec('table_list');
        map { $_->[1] } $res->is_success ? splice(@{ $res->result }, 1) : ();
    },
    type => [qw[
      Object Bool Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64
      Float Time ShortText Text LongText TokyoGeoPoint WGS84GeoPoint
    ]],
    # TODO XXX I'm not sure if these types can be applied to value_type
    value_type => [qw[
      Bool Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64
      Float Time TokyoGeoPoint WGS84GeoPoint
    ]],
    tokenizer => [qw[
      TokenBigram
      TokenBigramSplitSymbol
      TokenBigramSplitSymbolAlpha
      TokenBigramSplitSymbolAlphaDigit
      TokenBigramIgnoreBlank
      TokenBigramIgnoreBlankSplitSymbol
      TokenBigramIgnoreBlankSplitAlpha
      TokenBigramIgnoreBlankSplitAlphaDigit
      TokenDelimit
      TokenDelimitNull
      TokenTrigram
      TokenUnigram
    ]],
    normalizer => [qw[
      NormalizerAuto
      NormalizerNFKC51
    ]],
    # See log_level, log_put
    level => [qw[ EMERG ALERT CRIT error warning notice info debug ]],
);
$GroongaOptions{key_type} = $GroongaOptions{type};
$GroongaOptions{default_tokenizer} = $GroongaOptions{tokenizer};

our %GroongaCommands = (
    cache_limit => {
        args => [qw[ max ]],
    },
    check => {
        args => [qw[ obj ]],
    },
    clearlock => {
        args => [qw[ objname ]],
    },
    column_create => {
        args => [qw[ table name flags type source ]],
        opts => {
            flags => [qw[
              COLUMN_SCALAR
              COLUMN_VECTOR
              COLUMN_INDEX
              COMPRESS_ZLIB
              COMPRESS_LZO
              WITH_SECTION
              WITH_WEIGHT
              WITH_POSITION
            ]],
        },
    },
    column_list => {
        args => [qw[ table ]],
    },
    column_remove => {
        args => [qw[ table name ]],
    },
    column_rename => {
        args => [qw[ table name new_name ]],
    },
    define_selector => {
        args => [qw[
          name
          table
          match_columns
          query
          filter
          scorer
          sortby
          output_columns
          offset
          limit
          drilldown
          drilldown_sortby
          drilldown_output_columns
          drilldown_offset
          drilldown_limit
        ]],
    },
    defrag => {
        args => [qw[ objname threshold ]],
    },
    delete => {
        args => [qw[ table key id filter ]],
    },
    dump => {
        args => [qw[ tables ]],
        opts => {
            tables => sub { $GroongaOptions{table}->(@_) },
        },
    },
    load => {
        args => [qw[ values table columns ifexists input_type ]],
    },
    log_level => {
        args => [qw[ level ]],
    },
    log_put => {
        args => [qw[ level message ]],
    },
    log_reopen => {},
    normalize => {
        args => [qw[ normalizer string flags ]],
        opts => {
            flags => [qw[ NONE REMOVE_BLANK WITH_TYPES WITH_CHECKS REMOVE_TOKENIZED_DELIMITER ]],
        },
    },
    quit => {},
    register => {
        args => [qw[ path ]],
    },
    ruby_eval => {
        args => [qw[ script ]],
    },
    ruby_load => {
        args => [qw[ path ]],
    },
    select => {
        args => [qw[
          table
          match_columns
          query
          filter
          scorer
          sortby
          output_columns
          offset
          limit
          drilldown
          drilldown_sortby
          drilldown_output_columns
          drilldown_offset
          drilldown_limit
          cache
          match_escalation_threshold
          query_expansion
          query_flags
          query_expander
        ]],
    },
    shutdown => {},
    status => {},
    suggest => {
        args => [qw[
          types
          table
          column
          query
          sortby
          output_columns
          offset
          limit
          frequency_threshold
          conditional_probability_threshold
          prefix_search
        ]],
        opts => {
            types => [qw[ complete correct suggest ]],
        },
    },
    table_create => {
        args => [qw[
          name
          flags
          key_type
          value_type
          default_tokenizer
          normalizer
        ]],
        opts => {
            flags => [qw[
              TABLE_NO_KEY
              TABLE_HASH_KEY
              TABLE_PAT_KEY
              TABLE_DAT_KEY
              KEY_WITH_SIS
            ]],
        },
    },
    table_list => {},
    table_remove => {
        args => [qw[ name ]],
        opts => {
            name => sub { $GroongaOptions{table}->(@_) },
        },
    },
    tokenize => {
        args => [qw[ tokenizer string normalizer flags ]],
        opts => {
            flags => [qw[ NONE ENABLE_TOKENIZED_DELIMITER ]],
        },
    },
    truncate => {
        args => [qw[ table ]],
    },
);

1;

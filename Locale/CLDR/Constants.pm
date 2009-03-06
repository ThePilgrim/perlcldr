# Constants for CLDR
package Locale::CLDR::Constants;

use base 'Exporter';

use constant {
  CALENDAR_FORMAT_FULL                  => 1,
  CALENDAR_FORMAT_NARROW                => 2,
  CALENDAR_FORMAT_SHORT                 => 3,
  CALENDAR_FORMAT_ABBREVIATED           => 4,
  CALENDAR_FORMAT_LONG                  => 5,
  CALENDAR_PERIOD                       => 6,
  CALENDAR_START_OF_WEEK                => 7,
  CALENDAR_TIMEZONE                     => 8,
  CALENDAR_TYPE_FORMATTED               => 9,
  CALENDAR_TYPE_GREGORIAN               => 10,
  CALENDAR_TYPE_NAME                    => 11,
  CALENDAR_TYPE_RFC822                  => 12,
  CALENDAR_TYPE_STANDALONE              => 13,
  CHARACTERS_AUXILIARY                  => 1,
  CHARACTERS_CURRENCY                   => 2,
  CHARACTERS_MAIN                       => 3,
  GET_CHARACTERS_EXEMPLARY              => 1,
  GET_CHARACTERS_MAPPING                => 2,
  GET_DATE_FORMAT                       => 3,
  GET_DAY_NAME                          => 4,
  GET_ERA_FROM_DATE                     => 5,
  GET_ERA_NAME                          => 6,
  GET_KEY_NAME                          => 7,
  GET_MONTH_NAME                        => 8,
  GET_IN_LIST                           => 9,
  GET_IN_TEXT                           => 10,
  GET_LANGUAGE_CODES                    => 11,
  GET_LANGUAGE_NAME                     => 12,
  GET_MEASUREMENT_PAPER_SIZE            => 13,
  GET_MEASUREMENT_SYSTEM                => 14,
  GET_MEASUREMENT_SYSTEM_NAME           => 15,
  GET_ORIENTATION                       => 16,
  GET_QUATER_NAME                       => 17,
  GET_QUOTES_ALTERNATE_CLOSE            => 18,
  GET_QUOTES_ALTERNATE_OPEN             => 19,
  GET_QUOTES_CLOSE                      => 20,
  GET_QUOTES_OPEN                       => 21,
  GET_SCRIPT_NAME                       => 22,
  GET_TERRITORY_NAME                    => 23,
  GET_TYPE_NAME                         => 24,
  GET_VARIANT_NAME                      => 25,
  IN_LIST_LOWERCASE_WORDS               => 1,
  IN_LIST_MIXED                         => 2,
  IN_LIST_TITLECASE_FIRST_WORD          => 3,
  IN_LIST_TITLECASE_WORDS               => 4,
  IN_TEXT_LOWERCASE_WORDS               => 1,
  IN_TEXT_TITLECASE_FIRST_WORD          => 2,
  IN_TEXT_TITLECASE_WORDS               => 3,
  IN_TEXT_TYPE_DAY_WIDTH                => 4,
  IN_TEXT_TYPE_CURRENCY                 => 5,
  IN_TEXT_TYPE_FIELDS                   => 6,
  IN_TEXT_TYPE_KEYS                     => 7,
  IN_TEXT_TYPE_LANGUAGES                => 8,
  IN_TEXT_TYPE_LONG                     => 9,
  IN_TEXT_TYPE_MEASUREMENT_SYSTEM_NAMES => 10,
  IN_TEXT_TYPE_MONTH_WIDTH              => 11,
  IN_TEXT_TYPE_QUATER_WIDTH             => 12,
  IN_TEXT_TYPE_SCRIPTS                  => 13,
  IN_TEXT_TYPE_TERRITORIES              => 14,
  IN_TEXT_TYPE_TYPES                    => 15,
  IN_TEXT_TYPE_VARIANTS                 => 16,
  IN_TEXT_MIXED                         => 17,
  KEY_CALANDAR                          => 1,
  KEY_COLLATION                         => 2,
  KEY_CURRENCY                          => 3,
  SEGMENT_GRAPHEME_CLUSTER              => 1,
  SEGMENT_LINE                          => 4,
  SEGMENT_SENTENCE                      => 3,
  SEGMENT_WORD                          => 2,
  TEXT_ORIENTATION_BOTTOM_TO_TOP        => 1,
  TEXT_ORIENTATION_LEFT_TO_RIGHT        => 2,
  TEXT_ORIENTATION_RIGHT_TO_LEFT        => 3,
  TEXT_ORIENTATION_TOP_TO_BOTTOM        => 4,
};

my @orientation = qw(
  TEXT_ORIENTATION_BOTTOM_TO_TOP
  TEXT_ORIENTATION_LEFT_TO_RIGHT
  TEXT_ORIENTATION_RIGHT_TO_LEFT
  TEXT_ORIENTATION_TOP_TO_BOTTOM
);

my @inlist = qw(
  IN_LIST_LOWERCASE_WORDS
  IN_LIST_MIXED
  IN_LIST_TITLECASE_FIRST_WORD
  IN_LIST_TITLECASE_WORDS
);

my @intext = qw(
  IN_TEXT_LOWERCASE_WORDS
  IN_TEXT_MIXED
  IN_TEXT_TITLECASE_FIRST_WORD
  IN_TEXT_TITLECASE_WORDS
  IN_TEXT_TYPE_CURRENCY
  IN_TEXT_TYPE_DAY_WIDTH
  IN_TEXT_TYPE_FIELDS
  IN_TEXT_TYPE_KEYS
  IN_TEXT_TYPE_LANGUAGES
  IN_TEXT_TYPE_LONG
  IN_TEXT_TYPE_MEASUREMENT_SYSTEM_NAME
  IN_TEXT_TYPE_MONTH_WIDTH
  IN_TEXT_TYPE_QUATER_WIDTH
  IN_TEXT_TYPE_SCRIPTS
  IN_TEXT_TYPE_TERRITORIES
  IN_TEXT_TYPE_TYPES
  IN_TEXT_TYPE_VARIANTS
);

my @internal = qw(
  GET_CHARACTERS_EXEMPLARY
  GET_CHARACTERS_MAPPING
  GET_DATE_FORMAT
  GET_DAY_NAME
  GET_ERA_FROM_DATE
  GET_ERA_NAME
  GET_KEY_NAME
  GET_MONTH_NAME
  GET_IN_LIST
  GET_IN_TEXT
  GET_LANGUAGE_CODES
  GET_LANGUAGE_NAME
  GET_MEASUREMENT_PAPER_SIZE
  GET_MEASUREMENT_SYSTEM
  GET_MEASUREMENT_SYSTEM_NAME
  GET_ORIENTATION
  GET_QUATER_NAME
  GET_QUOTES_ALTERNATE_CLOSE
  GET_QUOTES_ALTERNATE_OPEN
  GET_QUOTES_CLOSE
  GET_QUOTES_OPEN
  GET_SCRIPT_NAME
  GET_TERRITORY_NAME
  GET_TYPE_NAME
  GET_VARIANT_NAME
);

my @characters = qw(
  CHARACTERS_AUXILIARY
  CHARACTERS_CURRENCY
  CHARACTERS_MAIN
);

my @calendar = qw(
  CALENDAR_FORMAT_ABBREVIATED
  CALENDAR_FORMAT_FULL
  CALENDAR_FORMAT_LONG
  CALENDAR_FORMAT_NARROW
  CALENDAR_FORMAT_SHORT
  CALENDAR_PERIOD
  CALENDAR_START_OF_WEEK
  CALENDAR_TIMEZONE
  CALENDAR_TYPE_FORMATTED
  CALENDAR_TYPE_GREGORIAN
  CALENDAR_TYPE_NAME
  CALENDAR_TYPE_RFC822
  CALENDAR_TYPE_STANDALONE
);

my @segments = qw(
  SEGMENT_GRAPHEME_CLUSTER
  SEGMENT_LINE
  SEGMENT_SENTENCE
  SEGMENT_WORD
);

my @keys = qw(
  KEY_CALANDAR
  KEY_COLLATION
  KEY_CURRENCY
);

our @EXPORT_OK = (
  @orientation,
  @inlist,
  @intext,
  @internal,
  @characters,
  @calendar,
  @segments,
  @keys,
);

our %EXPORT_TAGS = (
  orientation => [@orientation],
  inlist      => [@inlist],
  intext      => [@intext],
  characters  => [@characters],
  internal    => [@internal],
  calendar    => [@calendar],
  segments    => [@segments],
  'keys'      => [@keys],
  all         => [
    @orientation,
    @inlist,
    @intext,
    @characters,
    @segments,
    @keys,
  ],
);

1;

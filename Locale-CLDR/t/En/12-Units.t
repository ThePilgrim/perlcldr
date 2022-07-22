#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 290;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('en_GB');

is($locale->unit(1, 'acre', 'narrow'), '1ac', 'English narrow 1 acre');
is($locale->unit(2, 'acre', 'narrow'), '2ac', 'English narrow 2 acres');
is($locale->unit(1, 'acre', 'short'), '1 ac', 'English short 1 acre');
is($locale->unit(2, 'acre', 'short'), '2 ac', 'English short 2 acres');
is($locale->unit(1, 'acre'), '1 acre', 'English long 1 acre');
is($locale->unit(2, 'acre'), '2 acres', 'English long 2 acres');
is($locale->unit(1, 'arc-minute', 'narrow'), '1′', 'English narrow 1 minute');
is($locale->unit(2, 'arc-minute', 'narrow'), '2′', 'English narrow 2 minutes');
is($locale->unit(1, 'arc-minute', 'short'), '1 arcmin', 'English short 1 arc minute');
is($locale->unit(2, 'arc-minute', 'short'), '2 arcmins', 'English short 2 arc minutes');
is($locale->unit(1, 'arc-minute'), '1 arcminute', 'English long 1 arc minute');
is($locale->unit(2, 'arc-minute'), '2 arcminutes', 'English long 2 arc minutes');
is($locale->unit(1, 'arc-second', 'narrow'), '1″', 'English narrow 1 second');
is($locale->unit(2, 'arc-second', 'narrow'), '2″', 'English narrow 2 seconds');
is($locale->unit(1, 'arc-second', 'short'), '1 arcsec', 'English short 1 arc second');
is($locale->unit(2, 'arc-second', 'short'), '2 arcsecs', 'English short 2 arc seconds');
is($locale->unit(1, 'arc-second'), '1 arcsecond', 'English long 1 arc second');
is($locale->unit(2, 'arc-second'), '2 arcseconds', 'English long 2 arc seconds');
is($locale->unit(1, 'celsius', 'narrow'), '1°', 'English narrow 1 degree Celsius');
is($locale->unit(2, 'celsius', 'narrow'), '2°', 'English narrow 2 degrees Celsius');
is($locale->unit(1, 'celsius', 'short'), '1°C', 'English short 1 degree Celsius');
is($locale->unit(2, 'celsius', 'short'), '2°C', 'English short 2 degrees Celsius');
is($locale->unit(1, 'celsius'), '1 degree Celsius', 'English long 1 degree Celsius');
is($locale->unit(2, 'celsius'), '2 degrees Celsius', 'English long 2 degrees Celsius');
is($locale->unit(1, 'centimeter', 'narrow'), '1cm', 'English narrow 1 centimetre');
is($locale->unit(2, 'centimeter', 'narrow'), '2cm', 'English narrow 2 centimetres');
is($locale->unit(1, 'centimeter', 'short'), '1 cm', 'English short 1 centimetre');
is($locale->unit(2, 'centimeter', 'short'), '2 cm', 'English short 2 centimetres');
is($locale->unit(1, 'centimeter'), '1 centimetre', 'English long 1 centimetre');
is($locale->unit(2, 'centimeter'), '2 centimetres', 'English long 2 centimetres');
is($locale->unit(1, 'cubic-kilometer', 'narrow'), '1km³', 'English narrow 1 cubic kilometre');
is($locale->unit(2, 'cubic-kilometer', 'narrow'), '2km³', 'English narrow 2 cubic kilometres');
is($locale->unit(1, 'cubic-kilometer', 'short'), '1 km³', 'English short 1 cubic kilometre');
is($locale->unit(2, 'cubic-kilometer', 'short'), '2 km³', 'English short 2 cubic kilometres');
is($locale->unit(1, 'cubic-kilometer'), '1 cubic kilometre', 'English long 1 cubic kilometre');
is($locale->unit(2, 'cubic-kilometer'), '2 cubic kilometres', 'English long 2 cubic kilometres');
is($locale->unit(1, 'cubic-mile', 'narrow'), '1mi³', 'English narrow 1 cubic mile');
is($locale->unit(2, 'cubic-mile', 'narrow'), '2mi³', 'English narrow 2 cubic miles');
is($locale->unit(1, 'cubic-mile', 'short'), '1 mi³', 'English short 1 cubic mile');
is($locale->unit(2, 'cubic-mile', 'short'), '2 mi³', 'English short 2 cubic miles');
is($locale->unit(1, 'cubic-mile'), '1 cubic mile', 'English long 1 cubic mile');
is($locale->unit(2, 'cubic-mile'), '2 cubic miles', 'English long 2 cubic miles');
is($locale->unit(1, 'day', 'narrow'), '1d', 'English narrow 1 day');
is($locale->unit(2, 'day', 'narrow'), '2d', 'English narrow 2 days');
is($locale->unit(1, 'day', 'short'), '1 day', 'English short 1 day');
is($locale->unit(2, 'day', 'short'), '2 days', 'English short 2 days');
is($locale->unit(1, 'day'), '1 day', 'English long 1 day');
is($locale->unit(2, 'day'), '2 days', 'English long 2 days');
is($locale->unit(1, 'degree', 'narrow'), '1°', 'English narrow 1 degree');
is($locale->unit(2, 'degree', 'narrow'), '2°', 'English narrow 2 degrees');
is($locale->unit(1, 'degree', 'short'), '1 deg', 'English short 1 degree');
is($locale->unit(2, 'degree', 'short'), '2 deg', 'English short 2 degree');
is($locale->unit(1, 'degree'), '1 degree', 'English long 1 degree');
is($locale->unit(2, 'degree'), '2 degrees', 'English long 2 degrees');
is($locale->unit(1, 'fahrenheit', 'narrow'), '1°F', 'English narrow 1 degree Fahrenheit');
is($locale->unit(2, 'fahrenheit', 'narrow'), '2°F', 'English narrow 2 degrees Fahrenheit');
is($locale->unit(1, 'fahrenheit', 'short'), '1°F', 'English short 1 degree Fahrenheit');
is($locale->unit(2, 'fahrenheit', 'short'), '2°F', 'English short 2 degrees Fahrenheit');
is($locale->unit(1, 'fahrenheit'), '1 degree Fahrenheit', 'English long 1 degree Fahrenheit');
is($locale->unit(2, 'fahrenheit'), '2 degrees Fahrenheit', 'English long 2 degrees Fahrenheit');
is($locale->unit(1, 'foot', 'narrow'), '1′', 'English narrow 1 foot');
is($locale->unit(2, 'foot', 'narrow'), '2′', 'English narrow 2 feet');
is($locale->unit(1, 'foot', 'short'), '1 ft', 'English short 1 foot');
is($locale->unit(2, 'foot', 'short'), '2 ft', 'English short 2 feet');
is($locale->unit(1, 'foot'), '1 foot', 'English long 1 foot');
is($locale->unit(2, 'foot'), '2 feet', 'English long 2 feet');
is($locale->unit(1, 'g-force', 'narrow'), '1G', 'English narrow 1 g-force');
is($locale->unit(2, 'g-force', 'narrow'), '2Gs', 'English narrow 2 g-force');
is($locale->unit(1, 'g-force', 'short'), '1 G', 'English short 1 g-force');
is($locale->unit(2, 'g-force', 'short'), '2 G', 'English short 2 g-force');
is($locale->unit(1, 'g-force'), '1 g-force', 'English long 1 g-force');
is($locale->unit(2, 'g-force'), '2 g-force', 'English long 2 g-force');
is($locale->unit(1, 'gram', 'narrow'), '1g', 'English narrow 1 gram');
is($locale->unit(2, 'gram', 'narrow'), '2g', 'English narrow 2 grams');
is($locale->unit(1, 'gram', 'short'), '1 g', 'English short 1 gram');
is($locale->unit(2, 'gram', 'short'), '2 g', 'English short 2 grams');
is($locale->unit(1, 'gram'), '1 gram', 'English long 1 gram');
is($locale->unit(2, 'gram'), '2 grams', 'English long 2 grams');
is($locale->unit(1, 'hectare', 'narrow'), '1ha', 'English narrow 1 hectare');
is($locale->unit(2, 'hectare', 'narrow'), '2ha', 'English narrow 2 hectares');
is($locale->unit(1, 'hectare', 'short'), '1 ha', 'English short 1 hectare');
is($locale->unit(2, 'hectare', 'short'), '2 ha', 'English short 2 hectares');
is($locale->unit(1, 'hectare'), '1 hectare', 'English long 1 hectare');
is($locale->unit(2, 'hectare'), '2 hectares', 'English long 2 hectares');
is($locale->unit(1, 'hectopascal', 'narrow'), '1hPa', 'English narrow 1 hectopascal');
is($locale->unit(2, 'hectopascal', 'narrow'), '2hPa', 'English narrow 2 hectopascals');
is($locale->unit(1, 'hectopascal', 'short'), '1 hPa', 'English short 1 hectopascal');
is($locale->unit(2, 'hectopascal', 'short'), '2 hPa', 'English short 2 hectopascals');
is($locale->unit(1, 'hectopascal'), '1 hectopascal', 'English long 1 hectopascal');
is($locale->unit(2, 'hectopascal'), '2 hectopascals', 'English long 2 hectopascals');
is($locale->unit(1, 'horsepower', 'narrow'), '1hp', 'English narrow 1 horsepower');
is($locale->unit(2, 'horsepower', 'narrow'), '2hp', 'English narrow 2 horsepower');
is($locale->unit(1, 'horsepower', 'short'), '1 hp', 'English short 1 horsepower');
is($locale->unit(2, 'horsepower', 'short'), '2 hp', 'English short 2 horsepower');
is($locale->unit(1, 'horsepower'), '1 horsepower', 'English long 1 horsepower');
is($locale->unit(2, 'horsepower'), '2 horsepower', 'English long 2 horsepower');
is($locale->unit(1, 'hour', 'narrow'), '1h', 'English narrow 1 hour');
is($locale->unit(2, 'hour', 'narrow'), '2h', 'English narrow 2 hours');
is($locale->unit(1, 'hour', 'short'), '1 hr', 'English short 1 hour');
is($locale->unit(2, 'hour', 'short'), '2 hrs', 'English short 2 hours');
is($locale->unit(1, 'hour'), '1 hour', 'English long 1 hour');
is($locale->unit(2, 'hour'), '2 hours', 'English long 2 hours');
is($locale->unit(1, 'inch', 'narrow'), '1″', 'English narrow 1 inch');
is($locale->unit(2, 'inch', 'narrow'), '2″', 'English narrow 2 inches');
is($locale->unit(1, 'inch', 'short'), '1 in', 'English short 1 inch');
is($locale->unit(2, 'inch', 'short'), '2 in', 'English short 2 inches');
is($locale->unit(1, 'inch'), '1 inch', 'English long 1 inch');
is($locale->unit(2, 'inch'), '2 inches', 'English long 2 inches');
is($locale->unit(1, 'inch-ofhg', 'narrow'), '1″ Hg', 'English narrow 1 inch of mercury');
is($locale->unit(2, 'inch-ofhg', 'narrow'), '2″ Hg', 'English narrow 2 inches of mercury');
is($locale->unit(1, 'inch-ofhg', 'short'), '1 inHg', 'English short 1 inch of mercury');
is($locale->unit(2, 'inch-ofhg', 'short'), '2 inHg', 'English short 2 inches of mercury');
is($locale->unit(1, 'inch-ofhg'), '1 inch of mercury', 'English long 1 inch of mercury');
is($locale->unit(2, 'inch-ofhg'), '2 inches of mercury', 'English long 2 inches of mercury');
is($locale->unit(1, 'kilogram', 'narrow'), '1kg', 'English narrow 1 kilogram');
is($locale->unit(2, 'kilogram', 'narrow'), '2kg', 'English narrow 2 kilograms');
is($locale->unit(1, 'kilogram', 'short'), '1 kg', 'English short 1 kilogram');
is($locale->unit(2, 'kilogram', 'short'), '2 kg', 'English short 2 kilograms');
is($locale->unit(1, 'kilogram'), '1 kilogram', 'English long 1 kilogram');
is($locale->unit(2, 'kilogram'), '2 kilograms', 'English long 2 kilograms');
is($locale->unit(1, 'kilometer', 'narrow'), '1km', 'English narrow 1 kilometre');
is($locale->unit(2, 'kilometer', 'narrow'), '2km', 'English narrow 2 kilometres');
is($locale->unit(1, 'kilometer', 'short'), '1 km', 'English short 1 kilometre');
is($locale->unit(2, 'kilometer', 'short'), '2 km', 'English short 2 kilometres');
is($locale->unit(1, 'kilometer'), '1 kilometre', 'English long 1 kilometre');
is($locale->unit(2, 'kilometer'), '2 kilometres', 'English long 2 kilometres');
is($locale->unit(1, 'kilometer-per-hour', 'narrow'), '1km/h', 'English narrow 1 kilometre per hour');
is($locale->unit(2, 'kilometer-per-hour', 'narrow'), '2km/h', 'English narrow 2 kilometres per hour');
is($locale->unit(1, 'kilometer-per-hour', 'short'), '1 km/h', 'English short 1 kilometre per hour');
is($locale->unit(2, 'kilometer-per-hour', 'short'), '2 km/h', 'English short 2 kilometres per hour');
is($locale->unit(1, 'kilometer-per-hour'), '1 kilometre per hour', 'English long 1 kilometre per hour');
is($locale->unit(2, 'kilometer-per-hour'), '2 kilometres per hour', 'English long 2 kilometres per hour');
is($locale->unit(1, 'kilowatt', 'narrow'), '1kW', 'English narrow 1 kilowatt');
is($locale->unit(2, 'kilowatt', 'narrow'), '2kW', 'English narrow 2 kilowatts');
is($locale->unit(1, 'kilowatt', 'short'), '1 kW', 'English short 1 kilowatt');
is($locale->unit(2, 'kilowatt', 'short'), '2 kW', 'English short 2 kilowatts');
is($locale->unit(1, 'kilowatt'), '1 kilowatt', 'English long 1 kilowatt');
is($locale->unit(2, 'kilowatt'), '2 kilowatts', 'English long 2 kilowatts');
is($locale->unit(1, 'light-year', 'narrow'), '1ly', 'English narrow 1 light year');
is($locale->unit(2, 'light-year', 'narrow'), '2ly', 'English narrow 2 light years');
is($locale->unit(1, 'light-year', 'short'), '1 ly', 'English short 1 light year');
is($locale->unit(2, 'light-year', 'short'), '2 ly', 'English short 2 light years');
is($locale->unit(1, 'light-year'), '1 light year', 'English long 1 light year');
is($locale->unit(2, 'light-year'), '2 light years', 'English long 2 light years');
is($locale->unit(1, 'liter', 'narrow'), '1l', 'English narrow 1 litre');
is($locale->unit(2, 'liter', 'narrow'), '2l', 'English narrow 2 litres');
is($locale->unit(1, 'liter', 'short'), '1 l', 'English short 1 litre');
is($locale->unit(2, 'liter', 'short'), '2 l', 'English short 2 litres');
is($locale->unit(1, 'liter'), '1 litre', 'English long 1 litre');
is($locale->unit(2, 'liter'), '2 litres', 'English long 2 litres');
is($locale->unit(1, 'meter', 'narrow'), '1m', 'English narrow 1 meter');
is($locale->unit(2, 'meter', 'narrow'), '2m', 'English narrow 2 meters');
is($locale->unit(1, 'meter', 'short'), '1 m', 'English short 1 meter');
is($locale->unit(2, 'meter', 'short'), '2 m', 'English short 2 meters');
is($locale->unit(1, 'meter'), '1 metre', 'English long 1 meter');
is($locale->unit(2, 'meter'), '2 metres', 'English long 2 meters');
is($locale->unit(1, 'meter-per-second', 'narrow'), '1m/s', 'English narrow 1 meter per second');
is($locale->unit(2, 'meter-per-second', 'narrow'), '2m/s', 'English narrow 2 meters per second');
is($locale->unit(1, 'meter-per-second', 'short'), '1 m/s', 'English short 1 meter per second');
is($locale->unit(2, 'meter-per-second', 'short'), '2 m/s', 'English short 2 meters per second');
is($locale->unit(1, 'meter-per-second'), '1 metre per second', 'English long 1 meter per second');
is($locale->unit(2, 'meter-per-second'), '2 metres per second', 'English long 2 meters per second');
is($locale->unit(1, 'mile', 'narrow'), '1mi', 'English narrow 1 mile');
is($locale->unit(2, 'mile', 'narrow'), '2mi', 'English narrow 2 miles');
is($locale->unit(1, 'mile', 'short'), '1 mi', 'English short 1 mile');
is($locale->unit(2, 'mile', 'short'), '2 mi', 'English short 2 miles');
is($locale->unit(1, 'mile'), '1 mile', 'English long 1 mile');
is($locale->unit(2, 'mile'), '2 miles', 'English long 2 miles');
is($locale->unit(1, 'mile-per-hour', 'narrow'), '1mph', 'English narrow 1 mile per hour');
is($locale->unit(2, 'mile-per-hour', 'narrow'), '2mph', 'English narrow 2 miles per hour');
is($locale->unit(1, 'mile-per-hour', 'short'), '1 mph', 'English short 1 mile per hour');
is($locale->unit(2, 'mile-per-hour', 'short'), '2 mph', 'English short 2 miles per hour');
is($locale->unit(1, 'mile-per-hour'), '1 mile per hour', 'English long 1 mile per hour');
is($locale->unit(2, 'mile-per-hour'), '2 miles per hour', 'English long 2 miles per hour');
is($locale->unit(1, 'millibar', 'narrow'), '1mb', 'English narrow 1 millibar');
is($locale->unit(2, 'millibar', 'narrow'), '2mb', 'English narrow 2 millibars');
is($locale->unit(1, 'millibar', 'short'), '1 mbar', 'English short 1 millibar');
is($locale->unit(2, 'millibar', 'short'), '2 mbar', 'English short 2 millibars');
is($locale->unit(1, 'millibar'), '1 millibar', 'English long 1 millibar');
is($locale->unit(2, 'millibar'), '2 millibars', 'English long 2 millibars');
is($locale->unit(1, 'millimeter', 'narrow'), '1mm', 'English narrow 1 millimetre');
is($locale->unit(2, 'millimeter', 'narrow'), '2mm', 'English narrow 2 millimetres');
is($locale->unit(1, 'millimeter', 'short'), '1 mm', 'English short 1 millimetre');
is($locale->unit(2, 'millimeter', 'short'), '2 mm', 'English short 2 millimetres');
is($locale->unit(1, 'millimeter'), '1 millimetre', 'English long 1 millimetre');
is($locale->unit(2, 'millimeter'), '2 millimetres', 'English long 2 millimetres');
is($locale->unit(1, 'millisecond', 'narrow'), '1ms', 'English narrow 1 millisecond');
is($locale->unit(2, 'millisecond', 'narrow'), '2ms', 'English narrow 2 milliseconds');
is($locale->unit(1, 'millisecond', 'short'), '1 ms', 'English short 1 millisecond');
is($locale->unit(2, 'millisecond', 'short'), '2 ms', 'English short 2 milliseconds');
is($locale->unit(1, 'millisecond'), '1 millisecond', 'English long 1 millisecond');
is($locale->unit(2, 'millisecond'), '2 milliseconds', 'English long 2 milliseconds');
is($locale->unit(1, 'minute', 'narrow'), '1m', 'English narrow 1 minute');
is($locale->unit(2, 'minute', 'narrow'), '2m', 'English narrow 2 minutes');
is($locale->unit(1, 'minute', 'short'), '1 min', 'English short 1 minute');
is($locale->unit(2, 'minute', 'short'), '2 mins', 'English short 2 minutes');
is($locale->unit(1, 'minute'), '1 minute', 'English long 1 minute');
is($locale->unit(2, 'minute'), '2 minutes', 'English long 2 minutes');
is($locale->unit(1, 'month', 'narrow'), '1m', 'English narrow 1 month');
is($locale->unit(2, 'month', 'narrow'), '2m', 'English narrow 2 months');
is($locale->unit(1, 'month', 'short'), '1 mth', 'English short 1 month');
is($locale->unit(2, 'month', 'short'), '2 mths', 'English short 2 months');
is($locale->unit(1, 'month'), '1 month', 'English long 1 month');
is($locale->unit(2, 'month'), '2 months', 'English long 2 months');
is($locale->unit(1, 'ounce', 'narrow'), '1oz', 'English narrow 1 ounce');
is($locale->unit(2, 'ounce', 'narrow'), '2oz', 'English narrow 2 ounces');
is($locale->unit(1, 'ounce', 'short'), '1 oz', 'English short 1 ounce');
is($locale->unit(2, 'ounce', 'short'), '2 oz', 'English short 2 ounces');
is($locale->unit(1, 'ounce'), '1 ounce', 'English long 1 ounce');
is($locale->unit(2, 'ounce'), '2 ounces', 'English long 2 ounces');
is($locale->unit(1, 'millimeter-per-second', 'narrow'), '1mm/s', 'English narrow 1 millimetre per second');
is($locale->unit(2, 'millimeter-per-second', 'narrow'), '2mm/s', 'English narrow 2 millimetres per second');
is($locale->unit(1, 'millimeter-per-second', 'short'), '1 mm/s', 'English short 1 millimetre per second');
is($locale->unit(2, 'millimeter-per-second', 'short'), '2 mm/s', 'English short 2 millimetres per second');
is($locale->unit(1, 'millimeter-per-second'), '1 millimetre per second', 'English long 1 millimetre per second');
is($locale->unit(2, 'millimeter-per-second'), '2 millimetres per second', 'English long 2 millimetres per second');
is($locale->unit(1, 'picometer', 'narrow'), '1pm', 'English narrow 1 picometre');
is($locale->unit(2, 'picometer', 'narrow'), '2pm', 'English narrow 2 picometres');
is($locale->unit(1, 'picometer', 'short'), '1 pm', 'English short 1 picometre');
is($locale->unit(2, 'picometer', 'short'), '2 pm', 'English short 2 picometres');
is($locale->unit(1, 'picometer'), '1 picometre', 'English long 1 picometre');
is($locale->unit(2, 'picometer'), '2 picometres', 'English long 2 picometres');
is($locale->unit(1, 'pound', 'narrow'), '1lb', 'English narrow 1 pound');
is($locale->unit(2, 'pound', 'narrow'), '2lb', 'English narrow 2 pounds');
is($locale->unit(1, 'pound', 'short'), '1 lb', 'English short 1 pound');
is($locale->unit(2, 'pound', 'short'), '2 lb', 'English short 2 pounds');
is($locale->unit(1, 'pound'), '1 pound', 'English long 1 pound');
is($locale->unit(2, 'pound'), '2 pounds', 'English long 2 pounds');
is($locale->unit(1, 'second', 'narrow'), '1s', 'English narrow 1 second');
is($locale->unit(2, 'second', 'narrow'), '2s', 'English narrow 2 seconds');
is($locale->unit(1, 'second', 'short'), '1 sec', 'English short 1 second');
is($locale->unit(2, 'second', 'short'), '2 secs', 'English short 2 seconds');
is($locale->unit(1, 'second'), '1 second', 'English long 1 second');
is($locale->unit(2, 'second'), '2 seconds', 'English long 2 seconds');
is($locale->unit(1, 'square-foot', 'narrow'), '1ft²', 'English narrow 1 square foot');
is($locale->unit(2, 'square-foot', 'narrow'), '2ft²', 'English narrow 2 square feet');
is($locale->unit(1, 'square-foot', 'short'), '1 sq ft', 'English short 1 square foot');
is($locale->unit(2, 'square-foot', 'short'), '2 sq ft', 'English short 2 square feet');
is($locale->unit(1, 'square-foot'), '1 square foot', 'English long 1 square foot');
is($locale->unit(2, 'square-foot'), '2 square feet', 'English long 2 square feet');
is($locale->unit(1, 'square-kilometer', 'narrow'), '1km²', 'English narrow 1 square kilometre');
is($locale->unit(2, 'square-kilometer', 'narrow'), '2km²', 'English narrow 2 square kilometres');
is($locale->unit(1, 'square-kilometer', 'short'), '1 km²', 'English short 1 square kilometre');
is($locale->unit(2, 'square-kilometer', 'short'), '2 km²', 'English short 2 square kilometres');
is($locale->unit(1, 'square-kilometer'), '1 square kilometre', 'English long 1 square kilometre');
is($locale->unit(2, 'square-kilometer'), '2 square kilometres', 'English long 2 square kilometres');
is($locale->unit(1, 'square-meter', 'narrow'), '1m²', 'English narrow 1 square meter');
is($locale->unit(2, 'square-meter', 'narrow'), '2m²', 'English narrow 2 square meters');
is($locale->unit(1, 'square-meter', 'short'), '1 m²', 'English short 1 square meter');
is($locale->unit(2, 'square-meter', 'short'), '2 m²', 'English short 2 square metres');
is($locale->unit(1, 'square-meter'), '1 square metre', 'English long 1 square metre');
is($locale->unit(2, 'square-meter'), '2 square metres', 'English long 2 square metres');
is($locale->unit(1, 'square-mile', 'narrow'), '1mi²', 'English narrow 1 square mile');
is($locale->unit(2, 'square-mile', 'narrow'), '2mi²', 'English narrow 2 square miles');
is($locale->unit(1, 'square-mile', 'short'), '1 sq mi', 'English short 1 square mile');
is($locale->unit(2, 'square-mile', 'short'), '2 sq mi', 'English short 2 square miles');
is($locale->unit(1, 'square-mile'), '1 square mile', 'English long 1 square mile');
is($locale->unit(2, 'square-mile'), '2 square miles', 'English long 2 square miles');
is($locale->unit(1, 'watt', 'narrow'), '1W', 'English narrow 1 watt');
is($locale->unit(2, 'watt', 'narrow'), '2W', 'English narrow 2 watts');
is($locale->unit(1, 'watt', 'short'), '1 W', 'English short 1 watt');
is($locale->unit(2, 'watt', 'short'), '2 W', 'English short 2 watts');
is($locale->unit(1, 'watt'), '1 watt', 'English long 1 watt');
is($locale->unit(2, 'watt'), '2 watts', 'English long 2 watts');
is($locale->unit(1, 'week', 'narrow'), '1w', 'English narrow 1 week');
is($locale->unit(2, 'week', 'narrow'), '2w', 'English narrow 2 weeks');
is($locale->unit(1, 'week', 'short'), '1 wk', 'English short 1 week');
is($locale->unit(2, 'week', 'short'), '2 wks', 'English short 2 weeks');
is($locale->unit(1, 'week'), '1 week', 'English long 1 week');
is($locale->unit(2, 'week'), '2 weeks', 'English long 2 weeks');
is($locale->unit(1, 'yard', 'narrow'), '1yd', 'English narrow 1 yard');
is($locale->unit(2, 'yard', 'narrow'), '2yd', 'English narrow 2 yards');
is($locale->unit(1, 'yard', 'short'), '1 yd', 'English short 1 yard');
is($locale->unit(2, 'yard', 'short'), '2 yd', 'English short 2 yards');
is($locale->unit(1, 'yard'), '1 yard', 'English long 1 yard');
is($locale->unit(2, 'yard'), '2 yards', 'English long 2 yards');
is($locale->unit(1, 'year', 'narrow'), '1y', 'English narrow 1 year');
is($locale->unit(2, 'year', 'narrow'), '2y', 'English narrow 2 years');
is($locale->unit(1, 'year', 'short'), '1 yr', 'English short 1 year');
is($locale->unit(2, 'year', 'short'), '2 yrs', 'English short 2 years');
is($locale->unit(1, 'year'), '1 year', 'English long 1 year');
is($locale->unit(2, 'year'), '2 years', 'English long 2 years');
is($locale->duration_unit('hm', 1, 2), '1:02', 'English duration hour, minuet');
is($locale->duration_unit('hms', 1, 2, 3 ), '1:02:03', 'English duration hour, minuet, second');
is($locale->duration_unit('ms', 1, 2 ), '1:02', 'English duration minuet, second');
is($locale->is_yes('Yes'), 1, 'English is yes');
is($locale->is_yes('es'), 0, 'English is not yes');
is($locale->is_no('nO'), 1, 'English is no');
is($locale->is_no('N&'), 0, 'English is not no');
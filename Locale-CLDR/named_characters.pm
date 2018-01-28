package named_characters;

sub import {
    shift;
	$^H{charnames} = \&translator;
}

sub translator {
	return "\\N{@_}";
}

1;

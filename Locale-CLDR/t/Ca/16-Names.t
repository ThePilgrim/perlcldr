#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 24;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('ca_FR');
my $other_locale = Locale::CLDR->new('en_US');

is($locale->locale_name(), 'català (França)', 'Locale name from current locale');
is($locale->locale_name('fr_CA'), 'francès canadenc', 'Locale name from string');
is($locale->locale_name($other_locale), 'anglès americà', 'Locale name from other locale object');

is($locale->language_name(), 'català', 'Language name from current locale');
is($locale->language_name('fr'), 'francès', 'Language name from string');
is($locale->language_name($other_locale), 'anglès', 'Language name from other locale object');

my $all_languages = {
	'aa' => 'àfar',
	'ab' => 'abkhaz',
	'ace' => 'atjeh',
	'ach' => 'acoli',
	'ada' => 'adangme',
	'ady' => 'adigué',
	'ae' => 'avèstic',
	'af' => 'afrikaans',
	'afh' => 'afrihili',
	'agq' => 'aghem',
	'ain' => 'ainu',
	'ak' => 'àkan',
	'akk' => 'accadi',
	'akz' => 'alabama',
	'ale' => 'aleuta',
	'aln' => 'albanès geg',
	'alt' => 'altaic meridional',
	'am' => 'amhàric',
	'an' => 'aragonès',
	'ang' => 'anglès antic',
	'anp' => 'angika',
	'ar' => 'àrab',
	'ar_001' => 'àrab estàndard modern',
	'arc' => 'arameu',
	'arn' => 'mapudungu',
	'aro' => 'araona',
	'arp' => 'arapaho',
	'ars' => 'àrab najdi',
	'arw' => 'arauac',
	'arz' => 'àrab egipci',
	'as' => 'assamès',
	'asa' => 'pare',
	'ase' => 'llengua de signes americana',
	'ast' => 'asturià',
	'av' => 'àvar',
	'awa' => 'awadhi',
	'ay' => 'aimara',
	'az' => 'azerbaidjanès',
	'az@alt=short' => 'àzeri',
	'ba' => 'baixkir',
	'bal' => 'balutxi',
	'ban' => 'balinès',
	'bar' => 'bavarès',
	'bas' => 'basa',
	'bax' => 'bamum',
	'bbj' => 'ghomala',
	'be' => 'belarús',
	'bej' => 'beja',
	'bem' => 'bemba',
	'bez' => 'bena',
	'bfd' => 'bafut',
	'bfq' => 'badaga',
	'bg' => 'búlgar',
	'bgn' => 'balutxi occidental',
	'bho' => 'bhojpuri',
	'bi' => 'bislama',
	'bik' => 'bicol',
	'bin' => 'edo',
	'bkm' => 'kom',
	'bla' => 'blackfoot',
	'bm' => 'bambara',
	'bn' => 'bengalí',
	'bo' => 'tibetà',
	'br' => 'bretó',
	'bra' => 'braj',
	'brh' => 'brahui',
	'brx' => 'bodo',
	'bs' => 'bosnià',
	'bss' => 'akoose',
	'bua' => 'buriat',
	'bug' => 'bugui',
	'bum' => 'bulu',
	'byn' => 'bilin',
	'byv' => 'medumba',
	'ca' => 'català',
	'cad' => 'caddo',
	'car' => 'carib',
	'cay' => 'cayuga',
	'cch' => 'atsam',
	'ccp' => 'chakma',
	'ce' => 'txetxè',
	'ceb' => 'cebuà',
	'cgg' => 'chiga',
	'ch' => 'chamorro',
	'chb' => 'txibtxa',
	'chg' => 'txagatai',
	'chk' => 'chuuk',
	'chm' => 'mari',
	'chn' => 'pidgin chinook',
	'cho' => 'choctaw',
	'chp' => 'chipewyan',
	'chr' => 'cherokee',
	'chy' => 'xeiene',
	'ckb' => 'kurd central',
	'co' => 'cors',
	'cop' => 'copte',
	'cr' => 'cree',
	'crh' => 'tàtar de Crimea',
	'crs' => 'francès crioll de les Seychelles',
	'cs' => 'txec',
	'csb' => 'caixubi',
	'cu' => 'eslau eclesiàstic',
	'cv' => 'txuvaix',
	'cy' => 'gal·lès',
	'da' => 'danès',
	'dak' => 'dakota',
	'dar' => 'darguà',
	'dav' => 'taita',
	'de' => 'alemany',
	'de_AT' => 'alemany austríac',
	'de_CH' => 'alemany estàndard suís',
	'del' => 'delaware',
	'den' => 'slavi',
	'dgr' => 'dogrib',
	'din' => 'dinka',
	'dje' => 'zarma',
	'doi' => 'dogri',
	'dsb' => 'baix sòrab',
	'dua' => 'douala',
	'dum' => 'neerlandès mitjà',
	'dv' => 'divehi',
	'dyo' => 'diola',
	'dyu' => 'jula',
	'dz' => 'dzongka',
	'dzg' => 'dazaga',
	'ebu' => 'embu',
	'ee' => 'ewe',
	'efi' => 'efik',
	'egl' => 'emilià',
	'egy' => 'egipci antic',
	'eka' => 'ekajuk',
	'el' => 'grec',
	'elx' => 'elamita',
	'en' => 'anglès',
	'en_AU' => 'anglès australià',
	'en_CA' => 'anglès canadenc',
	'en_GB' => 'anglès britànic',
	'en_GB@alt=short' => 'anglès (GB)',
	'en_US' => 'anglès americà',
	'enm' => 'anglès mitjà',
	'eo' => 'esperanto',
	'es' => 'espanyol',
	'es_419' => 'espanyol hispanoamericà',
	'es_ES' => 'espanyol europeu',
	'es_MX' => 'espanyol de Mèxic',
	'et' => 'estonià',
	'eu' => 'basc',
	'ewo' => 'ewondo',
	'ext' => 'extremeny',
	'fa' => 'persa',
	'fan' => 'fang',
	'fat' => 'fanti',
	'ff' => 'ful',
	'fi' => 'finès',
	'fil' => 'filipí',
	'fj' => 'fijià',
	'fo' => 'feroès',
	'fon' => 'fon',
	'fr' => 'francès',
	'fr_CA' => 'francès canadenc',
	'fr_CH' => 'francès suís',
	'frc' => 'francès cajun',
	'frm' => 'francès mitjà',
	'fro' => 'francès antic',
	'frr' => 'frisó septentrional',
	'frs' => 'frisó oriental',
	'fur' => 'friülà',
	'fy' => 'frisó occidental',
	'ga' => 'irlandès',
	'gaa' => 'ga',
	'gag' => 'gagaús',
	'gan' => 'xinès gan',
	'gay' => 'gayo',
	'gba' => 'gbaya',
	'gd' => 'gaèlic escocès',
	'gez' => 'gueez',
	'gil' => 'gilbertès',
	'gl' => 'gallec',
	'glk' => 'gilaki',
	'gmh' => 'alt alemany mitjà',
	'gn' => 'guaraní',
	'goh' => 'alt alemany antic',
	'gom' => 'concani de Goa',
	'gon' => 'gondi',
	'gor' => 'gorontalo',
	'got' => 'gòtic',
	'grb' => 'grebo',
	'grc' => 'grec antic',
	'gsw' => 'alemany suís',
	'gu' => 'gujarati',
	'guc' => 'wayú',
	'guz' => 'gusí',
	'gv' => 'manx',
	'gwi' => 'gwich’in',
	'ha' => 'haussa',
	'hai' => 'haida',
	'hak' => 'xinès hakka',
	'haw' => 'hawaià',
	'he' => 'hebreu',
	'hi' => 'hindi',
	'hif' => 'hindi de Fiji',
	'hil' => 'híligaynon',
	'hit' => 'hitita',
	'hmn' => 'hmong',
	'ho' => 'hiri motu',
	'hr' => 'croat',
	'hsb' => 'alt sòrab',
	'hsn' => 'xinès xiang',
	'ht' => 'crioll d’Haití',
	'hu' => 'hongarès',
	'hup' => 'hupa',
	'hy' => 'armeni',
	'hz' => 'herero',
	'ia' => 'interlingua',
	'iba' => 'iban',
	'ibb' => 'ibibio',
	'id' => 'indonesi',
	'ie' => 'interlingue',
	'ig' => 'igbo',
	'ii' => 'yi sichuan',
	'ik' => 'inupiak',
	'ilo' => 'ilocano',
	'inh' => 'ingúix',
	'io' => 'ido',
	'is' => 'islandès',
	'it' => 'italià',
	'iu' => 'inuktitut',
	'ja' => 'japonès',
	'jam' => 'crioll anglès de Jamaica',
	'jbo' => 'lojban',
	'jgo' => 'ngomba',
	'jmc' => 'machame',
	'jpr' => 'judeopersa',
	'jrb' => 'judeoàrab',
	'jv' => 'javanès',
	'ka' => 'georgià',
	'kaa' => 'karakalpak',
	'kab' => 'cabilenc',
	'kac' => 'katxin',
	'kaj' => 'jju',
	'kam' => 'kamba',
	'kaw' => 'kawi',
	'kbd' => 'kabardí',
	'kbl' => 'kanembu',
	'kcg' => 'tyap',
	'kde' => 'makonde',
	'kea' => 'crioll capverdià',
	'ken' => 'kenyang',
	'kfo' => 'koro',
	'kg' => 'kongo',
	'kgp' => 'kaingà',
	'kha' => 'khasi',
	'kho' => 'khotanès',
	'khq' => 'koyra chiini',
	'ki' => 'kikuiu',
	'kj' => 'kuanyama',
	'kk' => 'kazakh',
	'kkj' => 'kako',
	'kl' => 'grenlandès',
	'kln' => 'kalenjin',
	'km' => 'khmer',
	'kmb' => 'kimbundu',
	'kn' => 'kannada',
	'ko' => 'coreà',
	'koi' => 'komi-permiac',
	'kok' => 'concani',
	'kos' => 'kosraeà',
	'kpe' => 'kpelle',
	'kr' => 'kanuri',
	'krc' => 'karatxai-balkar',
	'kri' => 'krio',
	'krl' => 'carelià',
	'kru' => 'kurukh',
	'ks' => 'caixmiri',
	'ksb' => 'shambala',
	'ksf' => 'bafia',
	'ksh' => 'kölsch',
	'ku' => 'kurd',
	'kum' => 'kúmik',
	'kut' => 'kutenai',
	'kv' => 'komi',
	'kw' => 'còrnic',
	'ky' => 'kirguís',
	'la' => 'llatí',
	'lad' => 'judeocastellà',
	'lag' => 'langi',
	'lah' => 'panjabi occidental',
	'lam' => 'lamba',
	'lb' => 'luxemburguès',
	'lez' => 'lesguià',
	'lg' => 'ganda',
	'li' => 'limburguès',
	'lij' => 'lígur',
	'lkt' => 'lakota',
	'lmo' => 'llombard',
	'ln' => 'lingala',
	'lo' => 'laosià',
	'lol' => 'mongo',
	'lou' => 'crioll francès de Louisiana',
	'loz' => 'lozi',
	'lrc' => 'luri septentrional',
	'lt' => 'lituà',
	'lu' => 'luba katanga',
	'lua' => 'luba-lulua',
	'lui' => 'luisenyo',
	'lun' => 'lunda',
	'luo' => 'luo',
	'lus' => 'mizo',
	'luy' => 'luyia',
	'lv' => 'letó',
	'lzh' => 'xinès clàssic',
	'lzz' => 'laz',
	'mad' => 'madurès',
	'maf' => 'mafa',
	'mag' => 'magahi',
	'mai' => 'maithili',
	'mak' => 'makassar',
	'man' => 'mandinga',
	'mas' => 'massai',
	'mde' => 'maba',
	'mdf' => 'mordovià moksa',
	'mdr' => 'mandar',
	'men' => 'mende',
	'mer' => 'meru',
	'mfe' => 'mauricià',
	'mg' => 'malgaix',
	'mga' => 'gaèlic irlandès mitjà',
	'mgh' => 'makhuwa-metto',
	'mgo' => 'meta’',
	'mh' => 'marshallès',
	'mi' => 'maori',
	'mic' => 'micmac',
	'min' => 'minangkabau',
	'mk' => 'macedoni',
	'ml' => 'malaiàlam',
	'mn' => 'mongol',
	'mnc' => 'manxú',
	'mni' => 'manipurí',
	'moh' => 'mohawk',
	'mos' => 'moore',
	'mr' => 'marathi',
	'mrj' => 'mari occidental',
	'ms' => 'malai',
	'mt' => 'maltès',
	'mua' => 'mundang',
	'mul' => 'llengües vàries',
	'mus' => 'creek',
	'mwl' => 'mirandès',
	'mwr' => 'marwari',
	'my' => 'birmà',
	'mye' => 'myene',
	'myv' => 'mordovià erza',
	'mzn' => 'mazanderani',
	'na' => 'nauruà',
	'nan' => 'xinès min del sud',
	'nap' => 'napolità',
	'naq' => 'nama',
	'nb' => 'noruec bokmål',
	'nd' => 'ndebele septentrional',
	'nds' => 'baix alemany',
	'nds_NL' => 'baix saxó',
	'ne' => 'nepalès',
	'new' => 'newari',
	'ng' => 'ndonga',
	'nia' => 'nias',
	'niu' => 'niueà',
	'nl' => 'neerlandès',
	'nl_BE' => 'flamenc',
	'nmg' => 'bissio',
	'nn' => 'noruec nynorsk',
	'nnh' => 'ngiemboon',
	'no' => 'noruec',
	'nog' => 'nogai',
	'non' => 'nòrdic antic',
	'nov' => 'novial',
	'nqo' => 'n’Ko',
	'nr' => 'ndebele meridional',
	'nso' => 'sotho septentrional',
	'nus' => 'nuer',
	'nv' => 'navaho',
	'nwc' => 'newari clàssic',
	'ny' => 'nyanja',
	'nym' => 'nyamwesi',
	'nyn' => 'nyankole',
	'nyo' => 'nyoro',
	'nzi' => 'nzema',
	'oc' => 'occità',
	'oj' => 'ojibwa',
	'om' => 'oromo',
	'or' => 'oriya',
	'os' => 'osseta',
	'osa' => 'osage',
	'ota' => 'turc otomà',
	'pa' => 'panjabi',
	'pag' => 'pangasinan',
	'pal' => 'pahlavi',
	'pam' => 'pampanga',
	'pap' => 'papiament',
	'pau' => 'palauà',
	'pcd' => 'picard',
	'pcm' => 'pidgin de Nigèria',
	'pdc' => 'alemany pennsilvanià',
	'peo' => 'persa antic',
	'pfl' => 'alemany palatí',
	'phn' => 'fenici',
	'pi' => 'pali',
	'pl' => 'polonès',
	'pms' => 'piemontès',
	'pnt' => 'pòntic',
	'pon' => 'ponapeà',
	'prg' => 'prussià',
	'pro' => 'provençal antic',
	'ps' => 'paixtu',
	'ps@alt=variant' => 'pushtu',
	'pt' => 'portuguès',
	'pt_BR' => 'portuguès del Brasil',
	'pt_PT' => 'portuguès de Portugal',
	'qu' => 'quítxua',
	'quc' => 'k’iche’',
	'raj' => 'rajasthani',
	'rap' => 'rapanui',
	'rar' => 'rarotongà',
	'rgn' => 'romanyès',
	'rm' => 'retoromànic',
	'rn' => 'rundi',
	'ro' => 'romanès',
	'ro_MD' => 'moldau',
	'rof' => 'rombo',
	'rom' => 'romaní',
	'root' => 'arrel',
	'ru' => 'rus',
	'rup' => 'aromanès',
	'rw' => 'ruandès',
	'rwk' => 'rwo',
	'sa' => 'sànscrit',
	'sad' => 'sandawe',
	'sah' => 'iacut',
	'sam' => 'arameu samarità',
	'saq' => 'samburu',
	'sas' => 'sasak',
	'sat' => 'santali',
	'sba' => 'ngambay',
	'sbp' => 'sangu',
	'sc' => 'sard',
	'scn' => 'sicilià',
	'sco' => 'escocès',
	'sd' => 'sindi',
	'sdc' => 'sasserès',
	'sdh' => 'kurd meridional',
	'se' => 'sami septentrional',
	'see' => 'seneca',
	'seh' => 'sena',
	'sel' => 'selkup',
	'ses' => 'songhai oriental',
	'sg' => 'sango',
	'sga' => 'irlandès antic',
	'sh' => 'serbocroat',
	'shi' => 'taixelhit',
	'shn' => 'xan',
	'shu' => 'àrab txadià',
	'si' => 'singalès',
	'sid' => 'sidamo',
	'sk' => 'eslovac',
	'sl' => 'eslovè',
	'sm' => 'samoà',
	'sma' => 'sami meridional',
	'smj' => 'sami lule',
	'smn' => 'sami d’Inari',
	'sms' => 'sami skolt',
	'sn' => 'shona',
	'snk' => 'soninke',
	'so' => 'somali',
	'sog' => 'sogdià',
	'sq' => 'albanès',
	'sr' => 'serbi',
	'srn' => 'sranan',
	'srr' => 'serer',
	'ss' => 'swazi',
	'ssy' => 'saho',
	'st' => 'sotho meridional',
	'su' => 'sondanès',
	'suk' => 'sukuma',
	'sus' => 'susú',
	'sux' => 'sumeri',
	'sv' => 'suec',
	'sw' => 'suahili',
	'sw_CD' => 'suahili del Congo',
	'swb' => 'comorià',
	'syc' => 'siríac clàssic',
	'syr' => 'siríac',
	'szl' => 'silesià',
	'ta' => 'tàmil',
	'te' => 'telugu',
	'tem' => 'temne',
	'teo' => 'teso',
	'ter' => 'terena',
	'tet' => 'tètum',
	'tg' => 'tadjik',
	'th' => 'tai',
	'ti' => 'tigrinya',
	'tig' => 'tigre',
	'tiv' => 'tiv',
	'tk' => 'turcman',
	'tkl' => 'tokelauès',
	'tkr' => 'tsakhur',
	'tl' => 'tagal',
	'tlh' => 'klingonià',
	'tli' => 'tlingit',
	'tly' => 'talix',
	'tmh' => 'amazic',
	'tn' => 'setswana',
	'to' => 'tongalès',
	'tog' => 'tonga',
	'tpi' => 'tok pisin',
	'tr' => 'turc',
	'trv' => 'taroko',
	'ts' => 'tsonga',
	'tsi' => 'tsimshià',
	'tt' => 'tàtar',
	'ttt' => 'tat meridional',
	'tum' => 'tumbuka',
	'tvl' => 'tuvaluà',
	'tw' => 'twi',
	'twq' => 'tasawaq',
	'ty' => 'tahitià',
	'tyv' => 'tuvinià',
	'tzm' => 'amazic del Marroc central',
	'udm' => 'udmurt',
	'ug' => 'uigur',
	'uga' => 'ugarític',
	'uk' => 'ucraïnès',
	'umb' => 'umbundu',
	'und' => 'idioma desconegut',
	'ur' => 'urdú',
	'uz' => 'uzbek',
	'vai' => 'vai',
	've' => 'venda',
	'vec' => 'vènet',
	'vep' => 'vepse',
	'vi' => 'vietnamita',
	'vls' => 'flamenc occidental',
	'vo' => 'volapük',
	'vot' => 'vòtic',
	'vun' => 'vunjo',
	'wa' => 'való',
	'wae' => 'walser',
	'wal' => 'wolaita',
	'war' => 'waray',
	'was' => 'washo',
	'wbp' => 'warlpiri',
	'wo' => 'wòlof',
	'wuu' => 'xinès wu',
	'xal' => 'calmuc',
	'xh' => 'xosa',
	'xmf' => 'mingrelià',
	'xog' => 'soga',
	'yao' => 'yao',
	'yap' => 'yapeà',
	'yav' => 'yangben',
	'ybb' => 'yemba',
	'yi' => 'ídix',
	'yo' => 'ioruba',
	'yue' => 'cantonès',
	'yue@alt=menu' => 'xinès, cantonès',
	'za' => 'zhuang',
	'zap' => 'zapoteca',
	'zbl' => 'símbols Bliss',
	'zea' => 'zelandès',
	'zen' => 'zenaga',
	'zgh' => 'amazic estàndard marroquí',
	'zh' => 'xinès',
	'zh@alt=menu' => 'xinès, mandarí',
	'zh_Hans' => 'xinès simplificat',
	'zh_Hans@alt=long' => 'xinès mandarí (simplificat)',
	'zh_Hant' => 'xinès tradicional',
	'zh_Hant@alt=long' => 'xinès mandarí (tradicional)',
	'zu' => 'zulu',
	'zun' => 'zuni',
	'zxx' => 'sense contingut lingüístic',
	'zza' => 'zaza',
};

is_deeply($locale->all_languages, $all_languages, 'All languages');

is($locale->script_name(), '', 'Script name from current locale');
is($locale->script_name('latn'), 'llatí', 'Script name from string');
is($locale->script_name($other_locale), '', 'Script name from other locale object');

my $all_scripts = {
	'Adlm' => 'adlam',
	'Afak' => 'afaka',
	'Aghb' => 'albanès caucàsic',
	'Ahom' => 'ahom',
	'Arab' => 'àrab',
	'Arab@alt=variant' => 'persoaràbic',
	'Armi' => 'arameu imperial',
	'Armn' => 'armeni',
	'Avst' => 'avèstic',
	'Bali' => 'balinès',
	'Bamu' => 'bamum',
	'Bass' => 'bassa vah',
	'Batk' => 'batak',
	'Beng' => 'bengalí',
	'Bhks' => 'bhaiksuki',
	'Blis' => 'símbols Bliss',
	'Bopo' => 'bopomofo',
	'Brah' => 'brahmi',
	'Brai' => 'braille',
	'Bugi' => 'buginès',
	'Buhd' => 'buhid',
	'Cakm' => 'chakma',
	'Cans' => 'síl·labes dels aborígens canadencs unificats',
	'Cari' => 'carià',
	'Cham' => 'cham',
	'Cher' => 'cherokee',
	'Cirt' => 'cirth',
	'Copt' => 'copte',
	'Cprt' => 'xipriota',
	'Cyrl' => 'ciríl·lic',
	'Cyrs' => 'ciríl·lic de l’antic eslau eclesiàstic',
	'Deva' => 'devanagari',
	'Dsrt' => 'deseret',
	'Dupl' => 'taquigrafia Duployé',
	'Egyd' => 'demòtic egipci',
	'Egyh' => 'hieràtic egipci',
	'Egyp' => 'jeroglífic egipci',
	'Elba' => 'elbasan',
	'Ethi' => 'etiòpic',
	'Geok' => 'georgià hucuri',
	'Geor' => 'georgià',
	'Glag' => 'glagolític',
	'Goth' => 'gòtic',
	'Gran' => 'grantha',
	'Grek' => 'grec',
	'Gujr' => 'gujarati',
	'Guru' => 'gurmukhi',
	'Hanb' => 'han amb bopomofo',
	'Hang' => 'hangul',
	'Hani' => 'han',
	'Hano' => 'hanunoo',
	'Hans' => 'simplificat',
	'Hans@alt=stand-alone' => 'han simplificat',
	'Hant' => 'tradicional',
	'Hant@alt=stand-alone' => 'han tradicional',
	'Hebr' => 'hebreu',
	'Hira' => 'hiragana',
	'Hluw' => 'jeroglífic anatoli',
	'Hmng' => 'pahawh hmong',
	'Hrkt' => 'katakana o hiragana',
	'Hung' => 'hongarès antic',
	'Inds' => 'escriptura de la vall de l’Indus',
	'Ital' => 'cursiva antiga',
	'Jamo' => 'jamo',
	'Java' => 'javanès',
	'Jpan' => 'japonès',
	'Jurc' => 'jürchen',
	'Kali' => 'kayah li',
	'Kana' => 'katakana',
	'Khar' => 'kharosthi',
	'Khmr' => 'khmer',
	'Khoj' => 'khoja',
	'Knda' => 'kannada',
	'Kore' => 'coreà',
	'Kpel' => 'kpelle',
	'Kthi' => 'kaithi',
	'Lana' => 'lanna',
	'Laoo' => 'lao',
	'Latf' => 'llatí fraktur',
	'Latg' => 'llatí gaèlic',
	'Latn' => 'llatí',
	'Lepc' => 'lepcha',
	'Limb' => 'limbu',
	'Lina' => 'lineal A',
	'Linb' => 'lineal B',
	'Lisu' => 'lisu',
	'Loma' => 'loma',
	'Lyci' => 'lici',
	'Lydi' => 'lidi',
	'Mahj' => 'mahajani',
	'Mand' => 'mandaic',
	'Mani' => 'maniqueu',
	'Maya' => 'jeroglífics maies',
	'Mend' => 'mende',
	'Merc' => 'cursiva meroítica',
	'Mero' => 'meroític',
	'Mlym' => 'malaiàlam',
	'Modi' => 'modi',
	'Mong' => 'mongol',
	'Moon' => 'moon',
	'Mroo' => 'mro',
	'Mtei' => 'manipurí',
	'Mult' => 'multani',
	'Mymr' => 'birmà',
	'Narb' => 'antic nord-aràbic',
	'Nbat' => 'nabateu',
	'Newa' => 'newar',
	'Nkgb' => 'geba',
	'Nkoo' => 'n’Ko',
	'Nshu' => 'nü shu',
	'Ogam' => 'ogham',
	'Olck' => 'santali',
	'Orkh' => 'orkhon',
	'Orya' => 'oriya',
	'Osge' => 'osage',
	'Osma' => 'osmanya',
	'Palm' => 'palmirè',
	'Pauc' => 'Pau Cin Hau',
	'Perm' => 'antic pèrmic',
	'Phag' => 'phagspa',
	'Phli' => 'pahlavi inscripcional',
	'Phlp' => 'psalter pahlavi',
	'Phlv' => 'pahlavi',
	'Phnx' => 'fenici',
	'Plrd' => 'pollard miao',
	'Prti' => 'parthià inscripcional',
	'Rjng' => 'rejang',
	'Roro' => 'rongo-rongo',
	'Runr' => 'rúnic',
	'Samr' => 'samarità',
	'Sara' => 'sarati',
	'Sarb' => 'sud-aràbic antic',
	'Saur' => 'saurashtra',
	'Sgnw' => 'escriptura de signes',
	'Shaw' => 'shavià',
	'Shrd' => 'shrada',
	'Sidd' => 'siddham',
	'Sind' => 'devangari',
	'Sinh' => 'singalès',
	'Sora' => 'sora sompeng',
	'Sund' => 'sundanès',
	'Sylo' => 'syloti nagri',
	'Syrc' => 'siríac',
	'Syre' => 'siríac estrangelo',
	'Syrj' => 'siríac occidental',
	'Syrn' => 'siríac oriental',
	'Tagb' => 'tagbanwa',
	'Takr' => 'takri',
	'Tale' => 'tai le',
	'Talu' => 'nou tai lue',
	'Taml' => 'tàmil',
	'Tang' => 'tangut',
	'Tavt' => 'tai viet',
	'Telu' => 'telugu',
	'Teng' => 'tengwar',
	'Tfng' => 'tifinagh',
	'Tglg' => 'tagàlog',
	'Thaa' => 'thaana',
	'Thai' => 'tailandès',
	'Tibt' => 'tibetà',
	'Tirh' => 'tirhut',
	'Ugar' => 'ugarític',
	'Vaii' => 'vai',
	'Visp' => 'llenguatge visible',
	'Wara' => 'varang kshiti',
	'Wole' => 'woleai',
	'Xpeo' => 'persa antic',
	'Xsux' => 'cuneïforme sumeri-accadi',
	'Yiii' => 'yi',
	'Zinh' => 'heretat',
	'Zmth' => 'notació matemàtica',
	'Zsye' => 'emoji',
	'Zsym' => 'símbols',
	'Zxxx' => 'sense escriptura',
	'Zyyy' => 'comú',
	'Zzzz' => 'escriptura desconeguda',
};

is_deeply($locale->all_scripts, $all_scripts, 'All scripts');

is($locale->region_name(), 'França', 'Region name from current locale');
is($locale->region_name('fr'), 'França', 'Region name from string');
is($locale->region_name($other_locale), 'Estats Units', 'Region name from other locale object');

my $all_regions = {
	'001' => 'Món',
	'002' => 'Àfrica',
	'003' => 'Amèrica del Nord',
	'005' => 'Amèrica del Sud',
	'009' => 'Oceania',
	'011' => 'Àfrica occidental',
	'013' => 'Amèrica Central',
	'014' => 'Àfrica oriental',
	'015' => 'Àfrica septentrional',
	'017' => 'Àfrica central',
	'018' => 'Àfrica meridional',
	'019' => 'Amèrica',
	'021' => 'Amèrica septentrional',
	'029' => 'Carib',
	'030' => 'Àsia oriental',
	'034' => 'Àsia meridional',
	'035' => 'Àsia sud-oriental',
	'039' => 'Europa meridional',
	'053' => 'Australàsia',
	'054' => 'Melanèsia',
	'057' => 'Regió de la Micronèsia',
	'061' => 'Polinèsia',
	'142' => 'Àsia',
	'143' => 'Àsia central',
	'145' => 'Àsia occidental',
	'150' => 'Europa',
	'151' => 'Europa oriental',
	'154' => 'Europa septentrional',
	'155' => 'Europa occidental',
	'202' => 'Àfrica subsahariana',
	'419' => 'Amèrica Llatina',
	'AC' => 'Illa de l’Ascensió',
	'AD' => 'Andorra',
	'AE' => 'Emirats Àrabs Units',
	'AF' => 'Afganistan',
	'AG' => 'Antigua i Barbuda',
	'AI' => 'Anguilla',
	'AL' => 'Albània',
	'AM' => 'Armènia',
	'AO' => 'Angola',
	'AQ' => 'Antàrtida',
	'AR' => 'Argentina',
	'AS' => 'Samoa Nord-americana',
	'AT' => 'Àustria',
	'AU' => 'Austràlia',
	'AW' => 'Aruba',
	'AX' => 'Illes Åland',
	'AZ' => 'Azerbaidjan',
	'BA' => 'Bòsnia i Hercegovina',
	'BB' => 'Barbados',
	'BD' => 'Bangladesh',
	'BE' => 'Bèlgica',
	'BF' => 'Burkina Faso',
	'BG' => 'Bulgària',
	'BH' => 'Bahrain',
	'BI' => 'Burundi',
	'BJ' => 'Benín',
	'BL' => 'Saint Barthélemy',
	'BM' => 'Bermudes',
	'BN' => 'Brunei',
	'BO' => 'Bolívia',
	'BQ' => 'Carib Neerlandès',
	'BR' => 'Brasil',
	'BS' => 'Bahames',
	'BT' => 'Bhutan',
	'BV' => 'Bouvet',
	'BW' => 'Botswana',
	'BY' => 'Belarús',
	'BZ' => 'Belize',
	'CA' => 'Canadà',
	'CC' => 'Illes Cocos',
	'CD' => 'Congo - Kinshasa',
	'CD@alt=variant' => 'Congo (RDC)',
	'CF' => 'República Centreafricana',
	'CG' => 'Congo - Brazzaville',
	'CG@alt=variant' => 'Congo (República del Congo)',
	'CH' => 'Suïssa',
	'CI' => 'Côte d’Ivoire',
 	'CI@alt=variant' => 'Costa d’Ivori',
	'CK' => 'Illes Cook',
	'CL' => 'Xile',
	'CM' => 'Camerun',
	'CN' => 'Xina',
	'CO' => 'Colòmbia',
	'CP' => 'Illa Clipperton',
	'CR' => 'Costa Rica',
	'CU' => 'Cuba',
	'CV' => 'Cap Verd',
	'CW' => 'Curaçao',
	'CX' => 'Illa Christmas',
	'CY' => 'Xipre',
	'CZ' => 'Txèquia',
	'CZ@alt=variant' => 'República Txeca',
	'DE' => 'Alemanya',
	'DG' => 'Diego Garcia',
	'DJ' => 'Djibouti',
	'DK' => 'Dinamarca',
	'DM' => 'Dominica',
	'DO' => 'República Dominicana',
	'DZ' => 'Algèria',
	'EA' => 'Ceuta i Melilla',
	'EC' => 'Equador',
	'EE' => 'Estònia',
	'EG' => 'Egipte',
	'EH' => 'Sàhara Occidental',
	'ER' => 'Eritrea',
	'ES' => 'Espanya',
	'ET' => 'Etiòpia',
	'EU' => 'Unió Europea',
	'EZ' => 'zona euro',
	'FI' => 'Finlàndia',
	'FJ' => 'Fiji',
	'FK' => 'Illes Malvines',
	'FK@alt=variant' => 'Illes Malvines (Illes Falkland)',
	'FM' => 'Micronèsia',
	'FO' => 'Illes Fèroe',
	'FR' => 'França',
	'GA' => 'Gabon',
	'GB' => 'Regne Unit',
	'GB@alt=short' => 'RU',
	'GD' => 'Grenada',
	'GE' => 'Geòrgia',
	'GF' => 'Guaiana Francesa',
	'GG' => 'Guernsey',
	'GH' => 'Ghana',
	'GI' => 'Gibraltar',
	'GL' => 'Groenlàndia',
	'GM' => 'Gàmbia',
	'GN' => 'Guinea',
	'GP' => 'Guadeloupe',
	'GQ' => 'Guinea Equatorial',
	'GR' => 'Grècia',
	'GS' => 'Illes Geòrgia del Sud i Sandwich del Sud',
	'GT' => 'Guatemala',
	'GU' => 'Guam',
	'GW' => 'Guinea Bissau',
	'GY' => 'Guyana',
	'HK' => 'Hong Kong (RAE Xina)',
	'HK@alt=short' => 'Hong Kong',
	'HM' => 'Illa Heard i Illes McDonald',
	'HN' => 'Hondures',
	'HR' => 'Croàcia',
	'HT' => 'Haití',
	'HU' => 'Hongria',
	'IC' => 'Illes Canàries',
	'ID' => 'Indonèsia',
	'IE' => 'Irlanda',
	'IL' => 'Israel',
	'IM' => 'Illa de Man',
	'IN' => 'Índia',
	'IO' => 'Territori Britànic de l’Oceà Índic',
	'IQ' => 'Iraq',
	'IR' => 'Iran',
	'IS' => 'Islàndia',
	'IT' => 'Itàlia',
	'JE' => 'Jersey',
	'JM' => 'Jamaica',
	'JO' => 'Jordània',
	'JP' => 'Japó',
	'KE' => 'Kenya',
	'KG' => 'Kirguizistan',
	'KH' => 'Cambodja',
	'KI' => 'Kiribati',
	'KM' => 'Comores',
	'KN' => 'Saint Christopher i Nevis',
	'KP' => 'Corea del Nord',
	'KR' => 'Corea del Sud',
	'KW' => 'Kuwait',
	'KY' => 'Illes Caiman',
	'KZ' => 'Kazakhstan',
	'LA' => 'Laos',
	'LB' => 'Líban',
	'LC' => 'Saint Lucia',
	'LI' => 'Liechtenstein',
	'LK' => 'Sri Lanka',
	'LR' => 'Libèria',
	'LS' => 'Lesotho',
	'LT' => 'Lituània',
	'LU' => 'Luxemburg',
	'LV' => 'Letònia',
	'LY' => 'Líbia',
	'MA' => 'Marroc',
	'MC' => 'Mònaco',
	'MD' => 'Moldàvia',
	'ME' => 'Montenegro',
	'MF' => 'Saint Martin',
	'MG' => 'Madagascar',
	'MH' => 'Illes Marshall',
	'MK' => 'Macedònia del Nord',
	'ML' => 'Mali',
	'MM' => 'Myanmar (Birmània)',
	'MN' => 'Mongòlia',
	'MO' => 'Macau (RAE Xina)',
	'MO@alt=short' => 'Macau',
	'MP' => 'Illes Mariannes del Nord',
	'MQ' => 'Martinica',
	'MR' => 'Mauritània',
	'MS' => 'Montserrat',
	'MT' => 'Malta',
	'MU' => 'Maurici',
	'MV' => 'Maldives',
	'MW' => 'Malawi',
	'MX' => 'Mèxic',
	'MY' => 'Malàisia',
	'MZ' => 'Moçambic',
	'NA' => 'Namíbia',
	'NC' => 'Nova Caledònia',
	'NE' => 'Níger',
	'NF' => 'Norfolk',
	'NG' => 'Nigèria',
	'NI' => 'Nicaragua',
	'NL' => 'Països Baixos',
	'NO' => 'Noruega',
	'NP' => 'Nepal',
	'NR' => 'Nauru',
	'NU' => 'Niue',
	'NZ' => 'Nova Zelanda',
	'OM' => 'Oman',
	'PA' => 'Panamà',
	'PE' => 'Perú',
	'PF' => 'Polinèsia Francesa',
	'PG' => 'Papua Nova Guinea',
	'PH' => 'Filipines',
	'PK' => 'Pakistan',
	'PL' => 'Polònia',
	'PM' => 'Saint-Pierre-et-Miquelon',
	'PN' => 'Illes Pitcairn',
	'PR' => 'Puerto Rico',
	'PS' => 'Territoris palestins',
	'PS@alt=short' => 'Palestina',
	'PT' => 'Portugal',
	'PW' => 'Palau',
	'PY' => 'Paraguai',
	'QA' => 'Qatar',
	'QO' => 'Territoris allunyats d’Oceania',
	'RE' => 'Illa de la Reunió',
	'RO' => 'Romania',
	'RS' => 'Sèrbia',
	'RU' => 'Rússia',
	'RW' => 'Ruanda',
	'SA' => 'Aràbia Saudita',
	'SB' => 'Illes Salomó',
	'SC' => 'Seychelles',
	'SD' => 'Sudan',
	'SE' => 'Suècia',
	'SG' => 'Singapur',
	'SH' => 'Saint Helena',
	'SI' => 'Eslovènia',
	'SJ' => 'Svalbard i Jan Mayen',
	'SK' => 'Eslovàquia',
	'SL' => 'Sierra Leone',
	'SM' => 'San Marino',
	'SN' => 'Senegal',
	'SO' => 'Somàlia',
	'SR' => 'Surinam',
	'SS' => 'Sudan del Sud',
	'ST' => 'São Tomé i Príncipe',
	'SV' => 'El Salvador',
	'SX' => 'Sint Maarten',
	'SY' => 'Síria',
	'SZ' => 'eSwatini',
	'SZ@alt=variant' => 'Swazilàndia',
	'TA' => 'Tristan da Cunha',
	'TC' => 'Illes Turks i Caicos',
	'TD' => 'Txad',
	'TF' => 'Territoris Australs Francesos',
	'TG' => 'Togo',
	'TH' => 'Tailàndia',
	'TJ' => 'Tadjikistan',
	'TK' => 'Tokelau',
	'TL' => 'Timor Oriental',
	'TL@alt=variant' => 'Timor Oriental',
	'TM' => 'Turkmenistan',
	'TN' => 'Tunísia',
	'TO' => 'Tonga',
	'TR' => 'Turquia',
	'TT' => 'Trinitat i Tobago',
	'TV' => 'Tuvalu',
	'TW' => 'Taiwan',
	'TZ' => 'Tanzània',
	'UA' => 'Ucraïna',
	'UG' => 'Uganda',
	'UM' => 'Illes Perifèriques Menors dels EUA',
	'UN' => 'Nacions Unides',
	'UN@alt=short' => 'ONU',
	'US' => 'Estats Units',
	'US@alt=short' => 'EUA',
	'UY' => 'Uruguai',
	'UZ' => 'Uzbekistan',
	'VA' => 'Ciutat del Vaticà',
	'VC' => 'Saint Vincent i les Grenadines',
	'VE' => 'Veneçuela',
	'VG' => 'Illes Verges Britàniques',
	'VI' => 'Illes Verges Nord-americanes',
	'VN' => 'Vietnam',
	'VU' => 'Vanuatu',
	'WF' => 'Wallis i Futuna',
	'WS' => 'Samoa',
	'XA' => 'pseudoaccents',
	'XB' => 'pseudobidi',
	'XK' => 'Kosovo',
	'YE' => 'Iemen',
	'YT' => 'Mayotte',
	'ZA' => 'República de Sud-àfrica',
	'ZM' => 'Zàmbia',
	'ZW' => 'Zimbàbue',
	'ZZ' => 'regió desconeguda',
};

is_deeply($locale->all_regions(), $all_regions, 'All Regions');

is($locale->variant_name(), '', 'Variant name from current locale');
is($locale->variant_name('HOGNORSK'), 'høgnorsk', 'Variant name from string');
is($locale->variant_name($other_locale), '', 'Variant name from other locale object');

is($locale->key_name('colCaseLevel'), 'ordenació per detecció de majúscules', 'Key name from string');

is($locale->type_name(colCaseFirst => 'lower'), 'Mostra primer les minúscules', 'Type name from string');

is($locale->measurement_system_name('metric'), 'mètric', 'Measurement system name English Metric');
is($locale->measurement_system_name('us'), 'EUA', 'Measurement system name English US');
is($locale->measurement_system_name('uk'), 'RU', 'Measurement system name English UK');
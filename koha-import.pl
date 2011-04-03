#!/usr/bin/perl
use warnings;
use strict;

use DBI;
use XML::Simple;
use Data::Dump qw(dump);

our $koha_dsn    = 'dbi:oursql:dbname=koha';
our $koha_user   = 'kohaadmin';
our $koha_passwd = '';

our $geo_dsn = 'dbi:Pg:dbname=koha';
our $geo_user = '';
our $geo_passwd = '';

our $opts = { RaiseError => 1 }; #, AutoCommit => 0, pg_enable_utf8 => 1, oursql_enable_utf8 => 1 };

require '/srv/koha-config.pl';

my $k_dbh = DBI->connect($koha_dsn, $koha_user, $koha_passwd, $opts) || die $DBI::errstr;
my $g_dbh = DBI->connect($geo_dsn, $geo_user, $geo_passwd, $opts) || die $DBI::errstr;

sub fetch_table {
	my ( $table, $pk ) = @_;

	warn "# clean $table";
	$g_dbh->do( "delete from $table" );

	my $offset = 0;

	my $sql = "select * from $table order by $pk";

	warn "# import $table";

	do {

		my $sth = $k_dbh->prepare( "$sql limit 1000 offset $offset" );
		print STDERR "$table [$offset] ";
		$sth->execute;

		$offset = 0 if ! $sth->rows; # exit

		my @cols = @{ $sth->{NAME_lc} };
		my $sql_insert = "insert into $table (" . join(',',@cols) . ") values (" . join(',', map { '?' } @cols ) . ")";
		my $sth_insert = $g_dbh->prepare( $sql_insert );

		while( my $row = $sth->fetchrow_arrayref ) {
			eval { $sth_insert->execute( @$row ) };
			$offset++;
			print STDERR "$offset " if $offset % 100 == 0;
		}

		print STDERR "\n";

	} while $offset;
}

#fetch_table 'biblio' => 'biblionumber' ;
#fetch_table 'biblioitems' => 'biblioitemnumber' ;

sub geo_biblioitems {

warn "# drop geo_biblioitems";
eval { $g_dbh->do(qq{ drop table geo_biblioitems }) };

warn "# create geo_biblioitems";
$g_dbh->do(qq{
create table geo_biblioitems (
	biblioitemnumber integer not null references biblioitems(biblioitemnumber),
	biblionumber integer not null references biblio(biblionumber),
	city text
)
});
my $sth_insert = $g_dbh->prepare(qq{
	insert into geo_biblioitems values (?,?,?)
});

warn "# select bibiloitems";
my $sth = $g_dbh->prepare(qq{
SELECT
	biblioitemnumber, biblionumber, isbn, issn, marcxml
from biblioitems
});
$sth->execute;

warn $sth->rows, " rows\n";

sub warn_dump {
	warn dump @_,$/ if $ENV{DEBUG};
}

my $i = 0;

while ( my $row = $sth->fetchrow_hashref ) {
	my $xml = XMLin( delete $row->{marcxml}, ForceArray => [ 'datafield', 'subfield' ] );

	warn_dump($row, $xml);

	my @tag_260 = grep { $_->{tag} eq '260' } @{ $xml->{datafield} };

	next unless @tag_260;

	warn_dump @tag_260 if $ENV{DEBUG};

	foreach my $sf ( @{ $tag_260[0]->{subfield} } ) {
		$row->{ 'tag_260_' . $sf->{code} } = $sf->{content};
	}

	$row->{city} = $row->{tag_260_a};
	$row->{city} =~ s/['"]+//g;
	$row->{city} =~ s/\s*\[etc.*\].*$//;
	$row->{city} =~ s/\s*[:]\s*$//;
	$row->{city} =~ s/[\[\]]+//g;

	warn_dump $row;

	warn "# $i ", $row->{city}, $/ if $i++ % 100 == 0;

	$sth_insert->execute( $row->{biblioitemnumber}, $row->{biblionumber}, $row->{city} );
}

} # geo_biblioitems;

#geo_biblioitems;

eval {
$g_dbh->do(qq{
create table geo_city (
	city_koha text not null primary key,
	city text,
	country text,
	county text,
	lat float,
	lng float,
	radius int,
	dump text
)
});
};

my $sth_insert = $g_dbh->prepare(qq{insert into geo_city values (?,?,?,?,?,?,?,?)});

my $sth = $g_dbh->prepare(qq{
select count(*),city from geo_biblioitems where city not in (select city_koha from geo_city) group by city order by count(city) desc
});
$sth->execute;

warn $sth->rows, " cities to geolocate";

use Geo::Coder::PlaceFinder;

my $geocoder = Geo::Coder::PlaceFinder->new( appid => 'eQWEGC58' );

while( my $row = $sth->fetchrow_hashref ) {
	my $location  = $geocoder->geocode(location => $row->{city});
	warn dump($location);
	$sth_insert->execute(
		$row->{city}
		, $location->{city},
		, $location->{country}
		, $location->{county}
		, $location->{latitude}
		, $location->{longitude}
		, $location->{radius}
		, dump($location)
	);
}

eval { $g_dbh->do(qq{ drop table geo_count }) };
$g_dbh->do(qq{

select
	count(biblionumber)
	,point(lat,lng)
	,geo_city.city
	,country
into geo_count
from geo_biblioitems
join geo_city on city_koha = geo_biblioitems.city
where length(geo_city.city) > 1
group by geo_city.city, country, lat, lng
order by count(biblionumber) desc

});

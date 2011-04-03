#!/usr/bin/perl
# Deliver click values to volcano.htm...
# Author. John D. Coryat 02/2010...
# Copyright 2010 USNaviguide LLC. All rights reserved...

use CGI qw/:standard *table/;
use strict ;
use DBI ;
use USNaviguide_Google_Tiles ;

my $dbh 	= DBI->connect ( "dbi:Pg:dbname=koha" , "dpavlin" , "" , { AutoCommit => 1 } ) ;
my $point	= param('POINT') ;
my $zoom	= param('ZOOM') ;

my $maxpix	= 15 ;					# Maximum pixels between click and point

my $limit_books = 100; # max. for one click

print qq{Content-type: text/xml\r\n\r\n};
print qq{<?xml version="1.0" encoding="UTF-8"?>\n} ;
print qq!<map>\n! ;

if ( !$point )
{
 print qq!<info error="No point passed..."/>\n! ;
 print qq!</map>\n! ;
 $dbh->disconnect ;
 exit ;
}

if ( $point =~ /(.*),(.*)/ )
{
 my $lat	= $1 ;
 my $lng	= $2 ;

 my $value = &Google_Tile_Factors($zoom) ;					# Calculate Tile Factors

 my ($latpix,$lngpix) = &Google_Coord_to_Pix( $value, $lat, $lng ) ;	# Convert coordinate to pixel location
 
 my $sql = qq{
select
	city_koha
	,country
	,count
	,point
	,point'($lat,$lng)' <-> point as distance
from geo_count
order by distance
limit 1
 };

 if ( my ($city,$country,$count,$volpnt,$i) = $dbh->selectrow_array($sql) )	# Got one
 {
  $volpnt =~ /\((.*),(.*)\)/ ; 
  my $vlat = $1 ;
  my $vlng = $2 ;

  my ($vlatpix,$vlngpix) = &Google_Coord_to_Pix( $value, $vlat, $vlng ) ;	# Convert coordinate to pixel location

  if ( sqrt(($vlatpix -	$latpix)**2  + ($vlngpix - $lngpix)**2) > $maxpix )
  {
   # Click not within maxpix of point...
   print qq!<info error="No publisher is within range of your click, please try again."/>\n! ;
  } else								# Good point found
  {

	my $sth = $dbh->prepare(qq{
select
	author, title, max(bi.biblionumber), count(title)
from geo_city c
join geo_biblioitems bi on bi.city = c.city_koha
join biblio b on b.biblionumber = bi.biblionumber
where c.city_koha = ? and country = ?
group by author, title
order by min(timestamp)
limit $limit_books
	});
	$sth->execute( $city, $country );

	my $rows = $sth->rows;
	if ( $rows == $limit_books ) {
		$rows = "more than $rows";
		$rows = $count if $count > $rows;
	};
	my $books = 'books';
	$books = 'book' if $rows == 1;

	my $descript = "<b>$city</b> <em>$country</em> <small>$rows $books</small>\n<ol>";

	while ( my $row = $sth->fetchrow_hashref ) {
		$descript .= sprintf qq|<li><a target="koha" href="http://koha.ffzg.hr/cgi-bin/koha/opac-detail.pl?biblionumber=%d">%s</a> %s\n|,
			$row->{biblionumber}, $row->{title}, $row->{author}
		;
	}

	$descript .= "\n</ol>\n";

   print qq!<info error=""  name="${city}_${country}" lat="$vlat" lng="$vlng">\n! ;
   print qq! <description><\![CDATA[$descript]]></description>\n! ;
   print qq!</info>\n! ;
  }
 }
} else
{
 print qq!<info error="No valid point ($point) passed. Should be: (lat,lng) format."/>\n! ;
}
$dbh->disconnect ;

print "</map>\n\n" ;


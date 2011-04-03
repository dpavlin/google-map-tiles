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

my $lat		= 0 ;
my $lng		= 0 ;
my $latpix	= 0 ;
my $lngpix	= 0 ;

my $volpnt	= '' ;
my $vlat	= 0 ;
my $vlng	= 0 ;
my $vlatpix	= 0 ;
my $vlngpix	= 0 ;

my $value	= '' ;
my $maxpix	= 15 ;					# Maximum pixels between click and point
my $descript	= '' ;
my $x		= '' ;
my $i		= 0 ;

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
 $lat	= $1 ;
 $lng	= $2 ;

 $value = &Google_Tile_Factors($zoom) ;					# Calculate Tile Factors

 ($latpix,$lngpix) = &Google_Coord_to_Pix( $value, $lat, $lng ) ;	# Convert coordinate to pixel location
 
 $x = "select city,country,count,point,point'($lat,$lng)' <-> point as distance from geo_count order by distance limit 1" ;

 if ( my ($city,$country,$count,$volpnt,$i) = $dbh->selectrow_array($x) )	# Got one
 {
  $volpnt =~ /\((.*),(.*)\)/ ; 
  $vlat = $1 ;
  $vlng = $2 ;

  ($vlatpix,$vlngpix) = &Google_Coord_to_Pix( $value, $vlat, $vlng ) ;	# Convert coordinate to pixel location

  if ( sqrt(($vlatpix -	$latpix)**2  + ($vlngpix - $lngpix)**2) > $maxpix )
  {
   # Click not within maxpix of point...
   print qq!<info error="No publisher is within range of your click, please try again."/>\n! ;
  } else								# Good point found
  {

	my $sth = $dbh->prepare(qq{
select
	author, title, bi.biblionumber
from geo_city c
join geo_biblioitems bi on bi.city = c.city_koha
join biblio b on b.biblionumber = bi.biblionumber
where c.city = ? and country = ?
order by timestamp
limit 100
	});
	$sth->execute( $city, $country );

	my $descript = "<b>$city</b> <em>$country</em> $count items\n<ol>";

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


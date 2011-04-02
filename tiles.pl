#!/usr/bin/perl -w
# Create Map overlay of worldwide volcanoes...
# Author. John D. Coryat 02/2010...
# Copyright 1997-2010 USNaviguide LLC. All rights reserved.

use DBI ;
use strict ;
use GD ;
use USNaviguide_Google_Tiles ;
use File::Path;

my $name = shift @ARGV || die "usage: $0 database\n";

warn "WORKING on $name\n";

my $zoom	= 0 ;
my $lat		= 0 ;
my $lng		= 0 ;
my $latpix	= 0 ;
my $lngpix	= 0 ;
my %tiles	= ( ) ;
my $tilex	= 0 ;
my $tiley	= 0 ;
my $nacount	= 0 ;
my %tile	= ( ) ;
my $top		= 0 ;
my $left	= 0 ;
my $count	= 0 ;
my $x		= '' ;
my $y		= '' ;
my $i		= 0 ;
my $j		= 0 ;
my $k		= 0 ;
my $ix		= 0 ;
my $iy		= 0 ;
my $im		= '' ;
my $white	= '' ;
my $sth		= '' ;
my $sti		= '' ;
my $curcol	= '' ;
my $value	= '' ;
my $file	= '' ;
my $imicon	= '' ;
my $imicon1	= '' ;
my $imicon2	= '' ;
my $maxzoom	= 10 ;
my $minzoom	= 2 ;
my $xiconoff	= 12 ;					# X Icon offset in pixels (width or lng)
my $yiconoff	= 12 ;					# Y Icon offset in pixels (height or lat)
my $xiconpix	= 24 ;					# Icon width in pixels
my $yiconpix	= 24 ;					# Icon width in pixels
my $path	= "$name/tiles" ;
my $icon1	= 'images/gvp_icon_1.png' ;		# Zooms up to 7
my $icon2	= 'images/gvp_icon_2.png' ;		# Zooms after 7
my $dbh 	= DBI->connect ( "dbi:Pg:dbname=$name" , "" , "" , { AutoCommit => 1 } ) ;

# Make sure icon file exists...

if ( !(-e $icon1) or !(-e $icon2))					# Icon file missing - bad thing
{
 print "Map Icon(s) missing\n" ;
 exit ;
}


# Relations: 
# Y,Top,N,S,Lat,Height
# X,Left,E,W,Lng,Width

# (35,-89),(34,-90)

eval { $dbh->do("drop table gvp_world_tiles") };
$dbh->do("create table gvp_world_tiles (zoom int2,tilex int4,tiley int4,latpix int4,lngpix int4)") ;

$sth = $dbh->prepare("select (volpnt)[0] as lat, (volpnt)[1] as lng from gvp_world") ;

$sth->execute ;

while ( ($lat,$lng) = $sth->fetchrow_array )
{
 $count++ ;

 # Figure out what tiles are needed...

 for ( $zoom = $minzoom; $zoom <= $maxzoom; $zoom++ )
 {
  $value = &Google_Tile_Factors($zoom) ; 		# Calculate Tile Factors

  ($latpix,$lngpix) = &Google_Coord_to_Pix( $value, $lat, $lng ) ;
  %tiles = ( ) ;

  ($tiley,$tilex) = &Google_Pix_to_Tile( $value, $latpix + $yiconoff, $lngpix + $xiconoff ) ;
  $tiles{"$tiley $tilex"} = [$tilex, $tiley] ;

  ($tiley,$tilex) = &Google_Pix_to_Tile( $value, $latpix + $yiconoff, $lngpix - $xiconoff ) ;
  $tiles{"$tiley $tilex"} = [$tilex, $tiley] ;

  ($tiley,$tilex) = &Google_Pix_to_Tile( $value, $latpix - $yiconoff, $lngpix + $xiconoff ) ;
  $tiles{"$tiley $tilex"} = [$tilex, $tiley] ;

  ($tiley,$tilex) = &Google_Pix_to_Tile( $value, $latpix - $yiconoff, $lngpix - $xiconoff ) ;
  $tiles{"$tiley $tilex"} = [$tilex, $tiley] ;

  foreach $x (keys %tiles)
  {
   $y = $tiles{$x} ;
   $dbh->do("insert into gvp_world_tiles (zoom,tilex,tiley,latpix,lngpix) values ($zoom,$$y[0],$$y[1],$latpix,$lngpix)" ) ;
  }
 }

 if ( int($count/100)*100 == $count )
 {
  print "Processed $count points...\n" ;
 }
}

# Make sure there have been records to process before continuing...

if ( !$count )
{
 $dbh->disconnect ;
 print "No records to process...\n" ;
 exit ;
}

print "Total Points: $count\n" ;

# Remove old images...

for ( $zoom = $minzoom; $zoom <= $maxzoom; $zoom++ )
{
 warn "clean $path/$zoom\n";
 rmtree "$path/$zoom";
 mkpath "$path/$zoom";
}
# Open up map icon files as images...

$imicon1 = GD::Image->newFromPng( $icon1 ) ;
$imicon2 = GD::Image->newFromPng( $icon2 ) ;

# Create index...

$dbh->do("create index gvp_world_tiles_main on gvp_world_tiles (zoom,tilex,tiley)") ;
$dbh->do("analyze gvp_world_tiles") ;

# Create tiles by zoom...

$sth = $dbh->prepare("select distinct zoom,tilex,tiley from gvp_world_tiles") ;

$sth->execute ;

$count = 0 ;

while ( ($zoom,$tilex,$tiley) = $sth->fetchrow_array )
{
 $count++ ;

 # Calculate tile fields...

 $file = $path . '/' . $zoom . '/v_' . $tilex . '_' . $tiley . '.png' ;

 ($top,$left) = &Google_Tile_to_Pix( $value, $tiley, $tilex ) ;

 # create a new image

 $im = new GD::Image(256,256,0) ;

 $white	= $im->colorAllocate(255,255,255) ;

 $im->interlaced('true') ;

 $im->transparent($white) ;

 $im->setThickness(1) ;

 # Calculate which icon to use based on zoom...

 if ( $zoom > 7 )
 {
  $imicon = $imicon2 ;
 } else
 {
  $imicon = $imicon1 ;
 }

 $sti = $dbh->prepare("select latpix,lngpix from gvp_world_tiles where zoom = $zoom and tilex = $tilex and tiley = $tiley") ;

 $sti->execute ;

 while ( ($latpix,$lngpix) = $sti->fetchrow_array )
 {
  $ix = $lngpix - $left - $xiconoff ;			# Remove half image size
  $iy = $latpix - $top - $yiconoff ;			# Remove half image size
  $im->copy($imicon,$ix,$iy,0,0,$xiconpix,$yiconpix) ;
 }

 open(my $PNG, '>', $file) || die "$file: $!";
 print $PNG $im->png ;
 close $PNG ;
# chmod(0444, $file) ;
 if ( int($count/100)*100 == $count )
 {
  print "Processed $count tiles...\n" ;
 }
}
print "Processed $count total tiles...\n" ;

#$dbh->do("drop table gvp_world_tiles") ;

# allow web server to select data
$dbh->do("grant select on gvp_world to public") ;

$dbh->disconnect ;


#!/usr/bin/perl
# Serve Map Tiles...
# Author. John D. Coryat 08/2007...

use CGI qw/:standard *table/ ;
use strict ;

my $zoom	= param('Z') ;				# Zoom
my $py		= param('Y') ;				# Y Tile Name
my $px		= param('X') ;				# X Tile Name
my $path	= $ENV{'DOCUMENT_ROOT'} . "/ws-2010-08/tiles" ;
$path = '/srv/google-map-markers-with-tile-layer/tiles';
my $i		= 0 ;
my $size	= 0 ;
my $x		= '' ;
my $file	= '' ;

if ( !defined($zoom) or !$zoom )			# Has to be a zoom
{
 exit ;
}

# v_9_6.png

$file	= "$path/$zoom/v_$px" . "_$py" . ".png" ;

print STDERR "$file\n" ;

$size	= ( -s $file ) ;

if ( !$size )						# not found
{
 $file	= $path . "/notiles.png" ;
 $size	= ( -s $file ) ;
}

if ( $size and open ( PNG, $file ) )
{
 read ( PNG, $x, $size ) ;
 close( PNG ) ;
 print header(-type=> 'image/png', -expires=> '+1d', -Pragma=> 'no-cache') ;

 print $x ;
} 

# END


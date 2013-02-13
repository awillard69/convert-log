#!/usr/bin/perl -w

# Convert a Cabrillo formatted log file from N1MM, as an ARCI contest, to 
# a NAQCC sprint submission log data.
#
# Anthony Willard
# 2012-11-26
#
use strict;
# set syntax warnings to errors, avoiding things like '=' versus '=='
use warnings FATAL => qw( syntax );
use Getopt::Long;

# setup
$/="\n"; # default input record delimiter
$,="\t"; # default output field delimiter
$\="\n"; # default output record delimiter

my( $inputfile, $outputfile, $helpfile, $xreffile );

GetOptions( "h" => \$helpfile,
		"i|input=s" => \$inputfile,
		"x|xref=s" => \$xreffile,
        "o|output=s" => \$outputfile
        );

# show any help if requested...
usage() if( defined( $helpfile ) );

# if we don't have any input log file, we have to stop...
if( !defined( $inputfile ) )
{
	print STDERR "Unable to proceed without a source input file.";
	print STDERR "";
	
	usage();
}

# open the input file...
open( INPUT, "<", $inputfile ) || die( "Cannot open input file $inputfile: \"$!\"" );

# if we have a designated output file, use it
if( defined( $outputfile ) )
{
	open( OUTPUT, ">", $outputfile ) || die( "Cannot open input file $outputfile: \"$!\"" );
}
else
{
	# otherwise, send the output to STDERR
	*OUTPUT = *STDERR;
}

my ( $qsocount, $membercount, $spccount, %spcmults, $ismember, $formatspec, %xref  );

if( defined( $xreffile ) )
{
	open( XREF, "<", $xreffile ) || die( "Unable to open xref file $xreffile: \"$!\"" );
	
	while( <XREF> )
	{
		chomp();
		chop();
		
		my $line = $_;
		if( $line =~ /^[0-9]+/ )
		{
			$line =~ s/ [ ]+/\;/g;  # remove extraneous spaces and replace with a ;
			$line =~ s/, /\;/g; # remove the delimiters for the CSZ
			
			#print STDERR $line;
			my @fields = split( /;/, $line );
			
			$xref{ $fields[2] } = $line ;
		}
	}
	
	close( XREF );
	
	print STDERR "Loaded " . scalar( keys( %xref ) ) . " cross reference entries." ;
}

# defaults
$qsocount = 0;
$membercount = 0;
$spccount = 0;

# set the format output spec
$formatspec = "%-11.11s%-4.4s%-5.5s%-11.11s%-4.4s%-7.7s%-8.8s%-4.4s";

# output a file header
print OUTPUT sprintf( $formatspec, "Call", "Bnd", "Time", "Worked", "SPC", "Nr/Pwr", "NewMult", "Pts" );

# QSO fields of interest
my ( $call, $band, $time, $worked, $spc, $power );

# read the input file...
while( <INPUT> )
{
	chomp();
	my $line = $_;
	
	# only process the QSO lines
	if( $line =~ /^QSO/ )
	{
		# increment the QSO count
		$qsocount++;
		
		# pluck out the fields
		$time = substr( $line, 25, 4 );
		$call = substr( $line, 30, 13 );
		$worked = substr( $line, 58, 13 );
		$spc = substr( $line, 77, 4 );
		$power = substr( $line, 82, 7 );
		$band = map_band( substr( $line, 4, 6 ) );
		
		# prepare any formatting by stripping any unwanted characters, like spaces
		$call =~ s/[ ]*//g;
		$worked =~ s/[ ]*//g;
		$spc =~ s/[ ]*//g;
		$power =~ s/[ ]*//g;
		
		# set some counter and tracking values...
		$spcmults{ $spc } += 1;
		$spccount = keys( %spcmults );
		
		# basic point for any QSO
		$ismember = 1;
		
		# set the member rate
		$ismember = 2 if( $power =~ /^[0-9][0-9][0-9][0-9]$/ );
		
		# if we have any cross reference data, we should compare it for clarity
		if(  %xref )
		{
			$ismember = 1; # reset this to validate here...
			
			# remove any section suffix, /0, /8, etc...
			$worked =~ s/\/[0-9]+$//g;
			
			if( defined( $xref{ $worked } ) )
			{
				my @data = split( /;/, $xref{ $worked } );
				
				if( $power ne $data[0] )
				{
					print STDERR "Contact $worked at $time indicated member number $power but cross reference shows " . $data[0];
				}
				
				if( $spc ne $data[4] )
				{
					print STDERR "Contact $worked at $time indicated state $spc but cross reference shows " . $data[4];
				}
				
				$ismember = 2;
			}
			else # not listed in the xref, so validate a member number or not...
			{
				if( $power =~ /^[0-9][0-9][0-9][0-9]$/ )
				{
					#print STDERR "Contact $worked at $time indicated a member ID but cannot verify, $power";
				}
			}
		}
		
		# increment the member counter
		$membercount++ if( $ismember == 2 );

		# if not a member, verify the power value is properly indicated
		# at this point we only warn...
		if( $ismember == 1 ) # nonmember, should have a power value
		{
			# if it doesn't look like #W, notify
			if( !( $power =~ /[0-9]+[M]*W/ ) )
			{
				print STDERR "***QSO with nonmember $worked at $time shows incorrect power";
			}
		}
		
		# members are members forever, but what if the number looks good but is invalid?
		# how do we compare it for accuracy, maybe look at the naqcc.dat file?  perhaps, check
		# the call with the number and exclude mismatched data?
		
		print OUTPUT sprintf( $formatspec, $call, $band, $time, $worked, $spc, $power, ($spcmults{ $spc } == 1 ? $spccount : "-"), $ismember );
	}
}

# housekeeping...
close( INPUT );

# summary time...
print STDERR "";
print STDERR "Summary stats for file $inputfile";
print STDERR "";
print STDERR "QSO Count    : " . $qsocount;
print STDERR "Member count : " . $membercount;
print STDERR "SPC Count    : " . $spccount;

# put commas into the final score summary
my $score = ( ( $qsocount + $membercount ) * $spccount );
$score =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;

print STDERR "Total points : " . $score;

exit;

# map a frequency to a band designator
sub map_band
{
	my ($freq) = @_;
	
	$freq =~ s/[ ]*//g;
	return( "160" ) if ( $freq =~ /^18[0-9][0-9]$/ );
	return( "80" ) if ( $freq =~ /^3[0-9][0-9][0-9]$/ );
	return( "40" ) if ( $freq =~ /^7[0-9][0-9][0-9]$/ );
	return( "20" ) if ( $freq =~ /^14[0-9][0-9][0-9]$/ );
	
	print STDERR "***Invalid band designation for QSO with $worked at $time z";
	return( "99" );
}

# usage
sub usage
{
	print STDERR "convert_log.pl: convert a Cabrillo format log from N1MM into the format required for a NAQCC Sprint format.";
	print STDERR "Usage";
	print STDERR "convert_log.pl -[i|input]=<log file> [-[o|output]=<output file>] [-x|xref=<naqcc reference file>]";
	print STDERR "\t<log file> is the name of the Cabrillo log file from N1MM";
	print STDERR "\t<output file> is the file to create with the reformatted data, if not provided, output goes to the screen";
	print STDERR "\t<naqcc reference file> is the NAQCC membership listing for cross checking.";
	
	exit( 99 );
}

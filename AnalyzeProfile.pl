#!/usr/bin/perl

################################################################################
# AnalyzeProfile.pl - analyzes the storageArrayProfile for disk array 
#   troubleshooting, gives a health check of the array
# RCS Keywords:
#     $Date: 2013-05-22 (Wed, 22 May 2013) $
#   $Source: /home/AnalyzeSCD.pl $
#   $Author: jr186037 $
# $Revision: 2.0.0.1 $
################################################################################

package AnalyzeProfile;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '2.0.0.1';       # version number
my $DEBUG = 0;                  # for debug mode
my $nohup = 0;                  # for non-interactive mode
my $MAXTRAY = 9;                # maximum number of trays
my $MAXSLOT = 24;               # maximum number of slots

# use this to set debug mode command line arguments
if ($DEBUG) { @ARGV = ('-n', 'storageArrayProfile9.txt'); }

################################################################################
#                              REVISION SUMMARY
################################################################################
# Fixed in 2.0.0.0
# - Match the whole line to print out the controller status.
# - Change the data structure which holds the volume information (hash instead
#   of array) so now I had to revamp the whole method of collecting volume info
# - Also fixed the minor bug of putting an extra space when no GHS is sparing
# - Finally, I also added the ability to print out what volumes are not Online
#   and what drives are not Optimal
# - Solved the issue of multiple volumes in a volume group
################################################################################
# Fixed in 2.0.0.1
# - Fixed some issues with the older versions of arrays (e.g. 5885's)
################################################################################

#-------------------------------------------------------------------------------


# print_version - prints the version
sub print_version {
    print "Array Profile Analyzer - Version $VERSION\n\n";
    return;
}

# print_usage_info - prints the usage information (including version)
sub print_usage_info {
    print_version;
    print "\n  Performs basic analysis of the storage array profile.\n\n";
    print 'Usage: perl AnalyzeProfile.pl [-n|-v|-?|storageArrayProfile.txt]';
    print "\n    -n, --nohup      Run without user input and print to STDOUT";
    print "\n    -v, --version    Print version number and exit";
    print "\n    -h, --help, -?   Print usage information and exit\n\n";
    return;
}

#-------------------------------------------------------------------------------

my $arg = $ARGV[0];    # $arg = command line argument

# if the argument is "-h" or "-?" or "--help" print usage information
if (
    ( !$arg ) || (
        $arg =~ m{^          # at start of string
                  (-h|       # match '-h'
                  -[?]|      # or '-?'
                  --help)    # or '--help'
                  $          # end of string
                 }xsim
    )
  )
{
    print_usage_info;
    exit 0;
}
# if the argument is "-v" or "--version" print version
elsif (
    $arg =~ m{^             # at start of string
              (-v|          # match '-v'
              --version)    # or '--version'
              $             # end of string
             }xsim
  )
{
    print_version;
    exit 0;
}
# if the argument is "-n" or "--nohup" run w/o input
elsif ($arg =~ m{^            # at start of string
                 (-n|         # match '-n'
                 --nohup)     # or '--nohup'
                 $            # end of string
                }xsim)
{
    $nohup = 1;
    $arg = $ARGV[1];
}

#-------------------------------------------------------------------------------

# read the MEL lines, format into appropriate data structures as necessary
# format into errors array
print_version;
print "Reading storageArrayProfile... ";
open(SAP, "<", "$arg") or die("Could not open file: $arg");
print "Done.\nBuilding data structures... ";

# $section - stores the current section we are in or '' if unknown/start
my $section = '';
# $subsection holds the current subsection within a section
my $subsection = '';

# $damc holds the name of the current DAMC in 'DAMCxxx-yy'
my $damc;

# %controllers holds the controller properties
#   $controllers{'A'}->{'status'=>status,'fw'=>fw,'type'=>type,'sn'=>sn,
#                       'volumes'=>[volumes]}... and similar for B
# $controller indicates whether it's controller A or controller B
my %controllers;
my $controller;

# %volumes holds the volume properties
#   $volumes[#]->{'status'=>status,'type'=type,
#                 'drives'=>[drives],'raid'=>raidlevel}
# %current_volume_info holds the volume properties until you know the volume
# $volume holds the name of the current volume
my %volumes;
my %current_volume_info;
my $volume;

# @drives holds the following drive properties
# $drives->[tray]->{'slot'}->{'status'=>status,'fw'=>fw}
my @drives;

# @hot_spares holds the hot spare locations
# %hot_spares_inuse indicates if that hot spare is actively in use
my @hot_spares;
my %hot_spares_inuse;

# @channels holds the drive channel properties
#   $channels[#]->{'status'=>status,'port'=>port}
my @channels;

while(<SAP>) {
    chomp;
    # See if we are at a boundary where we need to switch.
    if ($_ =~ m{^               # line starts with
                \s*             # (optional spaces)
                CONTROLLERS-    # 'CONTROLLERS-'
               }xsm)            # should catch ' CONTROLLERS---------'
    { $section = 'controllers'; }
    elsif ($_ =~ m{^          # line starts with
                   \s*        # (optional spaces)
                   VOLUME     # 'VOLUME'
                   \s         # a space
                   GROUPS-    # 'GROUPS-'
                  }xsm)       # should catch ' VOLUME GROUPS---------'
    { $section = 'volumes'; }
    elsif ($_ =~ m{^           # line starts with
                   STANDARD    # 'STANDARD'
                   \s          # a space
                   VOLUMES-    # 'VOLUMES-'
                  }xsm)        # should catch 'STANDARD VOLUMES--------'
    { $section = ''; }
    elsif ($_ =~ m{^          # line starts with
                   \s*        # (optional spaces)
                   DRIVES-    # 'DRIVES-'
                  }xsm)       # should catch ' DRIVES---------'
    { $section = 'drives'; }
    elsif ($_ =~ m{^            # line starts with
                   \s+          # space(s)
                   DRIVE        # 'DRIVE'
                   \s           # a space
                   CHANNELS:    # 'CHANNELS:'
                  }xsm)         # should catch ' DRIVE CHANNELS:'
    { $section = ''; }
    elsif ($_ =~ m{^            # line starts with
                   \s*          # (optional spaces)
                   # 'HOT SPARE COVERAGE:'
                   HOT \s SPARE \s COVERAGE:
                  }xsm)         # should catch ' HOT SPARE COVERAGE:'
    { $section = 'hot spares'; }
    elsif ($_ =~ m{^          # line starts with
                   \s+        # space(s)
                   DETAILS    # DETAILS
                   $          # end of line
                  }xsm)       # should catch ' DETAILS'
    { $section = ''; $subsection = ''; }
    elsif ($_ =~ m{^                    # line starts with
                   # 'PROFILE FOR STORAGE ARRAY:'
                   PROFILE \s FOR \s STORAGE \s ARRAY:
                   \s                   # a space
                   (DAMC\d+-\d+-\d+)    # 'DAMC###-##-##' (backref 1)
                  }xsm)
        # should catch 'PROFILE FOR STORAGE ARRAY: DAMC101-6-3'
    { $damc = $1; }
    if ($section eq 'controllers')
    {
        # if we are in the controllers section
        if ($_ =~ m{Controller \s in .+ Slot \s [0A]}xsm)
        # if 'Controller in ... Slot [0A]', set controller to 'a'
        { $controller = 'a'; $subsection = 'controller'; }
        elsif ($_ =~ m{Controller \s in .+ Slot \s [1B]}xsm)
        # if 'Controller in ... Slot [1B]', set controller to 'b'
        { $controller = 'b'; $subsection = 'controller'; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^          # line starts with
                       \s+        # space(s)
                       Status:    # 'Status:'
                       \s+        # space(s)
                       (.+)       # anything
                       \s*        # optional space(s)
                       $          # end of the line
                      }xsm)       # should catch ' Status: Optimal'
        { 
            my $temp = $1;
            $temp =~ s/^\s+|\s+$//g;
            $controllers{$controller}->{'status'} = $temp; 
        }
        elsif ($subsection eq 'controller' && 
               $_ =~ m{^                 # line starts with
                       \s+               # space(s)
                       Firmware          # 'Firmware'
                       \s                # space(s)
                       version:          # 'versions:'
                       \s+               # space(s)
                       ((\d+[.])+\d+)    # ##.##.##.## (backref 1)
                      }xsm)              # should catch 'Firmware version: ...'
        { $controllers{$controller}->{'fw'} = $1; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^        # line starts with
                       \s+      # space(s)
                       Board    # 'Board'
                       \s       # a space
                       ID:      # 'ID:'
                       \s+      # space(s)
                       (\d+)    # number(s) (backref 1)
                      }xsm)     # should catch ' Board ID:  2660'
        { $controllers{$controller}->{'type'} = $1; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^          # line starts with
                       \s+        # space(s)
                       # 'Serial number:'
                       Serial \s number:
                       \s+        # space(s)
                       (\w+)      # a word (backref 1)
                       \s*        # optional space(s)
                       $          # end of line
                      }xsm)       
        {
            $controllers{$controller}->{'sn'} = $1;
            $subsection = '';
        }
    }
    elsif ($section eq 'volumes')
    {
        # if we are in the volumes section
        if ($_ =~ m{^        # line starts with
                    \s+      # space(s)
                    Name:    # 'Name:'
                    \s+      # space(s)
                    (\S+)    # nonspace(s) (backref 1)
                    \s+      # space(s)
                    $        # end of line
                   }xsm)     # should catch ' Name:    10 '
        # we are in a new volume, so start changing information.
        { 
            $subsection = ''; 
            undef $volume;
            # assume the volume is one less than the volume group as a guess
            # NOTE: this is only possible with a fully numeric volume group...
            if ($1 !~ /\D/) { $volume = {$1-1 => 1}; }
            undef %current_volume_info;
        }
        # This next one is for match the format of older arrays (e.g. 5885's)
        elsif ($_ =~ m{^                  # line starts with
                       \s+                # space(s)
                       VOLUME \s GROUP    # 'VOLUME GROUP'
                       \s                 # a space
                       (\d+)              # number(s) (backref 1)
                       \s+                # space(s)
                       \(RAID\s           # '(RAID '
                       (\d+)              # number(s) (backref 2)
                       \)                 # ')'
                      }xsim)
            # should catch ' VOLUME GROUP (RAID 1)' (case insensitive)
        {
            $subsection = '';
            # assume the volume is one less than the volume group
            $volume = {$1-1 => 1};
            $current_volume_info{'raid'} = $2;
        }
        elsif (($_ =~ m{^          # line starts with
                        \s+        # space(s)
                        Status:    # 'Status:'
                        \s+        # space(s)
                        (\w+)      # a word (backref 1)
                        \s*        # optional space(s)
                        $          # end of line
                       }xsm) ||
               ($_ =~ m{^        # line starts with
                        \s+      # space(s)
                        # 'Volume group status:'
                        Volume \s group \s status:
                        \s+      # space(s)
                        (\w+)    # a word (backref 1)
                       }xsm))    # should catch ' Volume group status: Optimal'
        # store the volume's status
        { $current_volume_info{'status'} = $1; }
        elsif ($_ =~ m{^         # line starts with
                       \s+       # space(s)
                       RAID      # 'RAID'
                       \s        # a space
                       level:    # 'level:'
                       \s+       # space(s)
                       (\d+)     # number(s) (backref 1)
                       \s+       # space(s)
                       $         # end of line
                      }xsm)      # shoudl catch ' RAID level:    1 '
        # store the volume's RAID level
        { $current_volume_info{'raid'} = $1; }
        elsif ($_ =~ m{^              # line starts with
                       \s+            # space(s)
                       # 'Media' or 'Drive media' (backref 1)
                       (Media|
                       Drive \s media)
                       \s             # a space
                       type:          # 'type:'
                       \s+            # space(s)
                       ((\w+\s*)+)    # words and spaces (backref 2) until...
                       $              # end of line
                      }xsm)           # should catch ' Media type: Hard Disk...'
        # store the volume's media type (HDD vs SSD)
        { $current_volume_info{'type'} = $2; }
        elsif ($_ =~ m{^                    # line starts with
                       \s+                  # space(s)
                       Current \s owner:    # 'Current owner:'
                       ((\s*\S+)+)          # mix of space/nonspace (backref 1)
                       \s*                  # optional space(s)
                       $                    # end of line
                      }xsm) 
            # should catch '  Current owner:   Controller in slot A  '
        { 
            my $owner_string = $1;
            if ($owner_string =~ m{\sA}xsm) 
            { $current_volume_info{'owner'} = 'A'; }
            else 
            { $current_volume_info{'owner'} = 'B'; }
        }
        elsif ($_ =~ m{^       # line starts with
                       \s+     # space(s)
                       # 'Associated volumes'
                       Associated \s volumes
                      }xsm)    # should catch ' Associated drives'
        # set subsection for associated volumes to 'volume'
        { $subsection = 'volume'; undef $volume; }
        elsif ($subsection eq 'volume' &&
              ($_ =~ m{^            # line starts with
                       \s+          # space(s)
                       (\d+)        # number(s) (backref 1)
                       \s+          # space(s)
                       \S+ \s GB    # nonspace(s) a space and 'GB'
                       \s*          # optional space(s)
                       \w*          # an optional word
                       \s*          # optional space(s)
                       $            # end of line character
                      }xsm ||       # should catch '  34   267.903 GB  Yes  '
               $_ =~ m{^                # line starts with
                       \s+              # space(s)
                       (\d+)            # number(s) (backref 1)
                       \s+              # space(s)
                       \(\S+ \s GB\)    # nonspace(s) ' GB'
                       \s*              # optional space(s)
                       $                # end of line
                      }xsm))            # should catch '  0 (67.865 GB)  '
        {
            if (defined $volume) { $volume = {%$volume, $1 => 1}; }
            else { $volume = { $1 => 1 }; }
            $volumes{$1} = {
                'status' => $current_volume_info{'status'},
                'raid'   => $current_volume_info{'raid'},
                'type'   => $current_volume_info{'type'},
                'owner'  => $current_volume_info{'owner'}
             }
        }
        elsif ($_ =~ m{^       # line starts with
                       \s+     # space(s)
                       # 'Associated drives'
                       Associated \s drives
                      }xsm)    # should catch ' Associated drives'
        { 
            # set subsection for associated drives to 'drives'
            $subsection = 'drives';
            for my $vol (keys %$volume)
            {
                if (!(defined $volumes{$vol}))
                {
                    $volumes{$vol} = {
                        'status' => $current_volume_info{'status'},
                        'raid'   => $current_volume_info{'raid'},
                        'type'   => $current_volume_info{'type'},
                        'owner'  => $current_volume_info{'owner'}
                    }
                }
                $volumes{$vol}->{'drives'} = [];
            }
        }
        elsif ($subsection eq 'drives' &&
        # if we're in the associated drives section and we match the following
              ($_ =~ m{^        # line starts with
                       \s+      # space(s)
                       (\d+)    # number(s) (backref 1)
                       \s+      # space(s)
                       (\d+)    # number(s) (backref 2)
                      }xsm ||   # should catch ' 0    4'
               $_ =~ m{^                # line starts with
                       \s+              # space(s)
                       # 'Drive at Tray '
                       Drive \s at \s Tray \s
                       (\d+)            # number(s) (backref 1)
                       , \s Slot \s     # ', Slot '
                       (\d+)            # number(s) (backref 2)
                      }xsm))
            # the last part is for older arrays to catch:
            #   '  Drive at Tray 4, Slot 1 '
        {
            my ($tray, $slot) = ($1, $2);
            # add a space to slots less than 10 for printing later
            if ($slot < 10) { $slot = "$slot "; }
            # this is a basic "push" style adding of the new drive
            for my $vol (keys %$volume)
            {
                $volumes{$vol}->{'drives'} = 
                [@{$volumes{$vol}->{'drives'}}, "$tray,$slot"];
            }
        }
        
    }
    elsif($section eq 'drives')
    {
        if ($_ =~ m{^\s+                 # line starts with
                    (\d+),\s+(\d+)       # '##, ##' (backref 1 and 2)
                    \s+                  # space(s)
                    (\w+)                # a word (backref 3)
                    \s+                  # space(s)
                    \S+\s+GB             # non-space(s) ' GB'
                    \s+                  # space(s)
                    (\w+\s+\w+\s+\w+)    # 'WORD WORD WORD' (backref 4)
                    \s+                  # space(s)
                    \w+                  # a word
                    \s+                  # space(s)
                    \d+\s+Gbps           # number(s) ' Gbps'
                    \s+                  # space(s)
                    (\S+)                # non-space(s) (backref 5)
                    \s+                  # space(s)
                    (\w+)                # a word (backref 6)
                   }xsm)
            # should catch ' 1, 3  Optimal  333.33 GB  Hard Disk Drive ... '
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'type' => $4,
                                  'product id' => $5,
                                  'fw' => $6
                              }; }
        elsif ($_ =~ m{^\s+              # line starts with
                       (\d+),\s+(\d+)    # '##, ##' (backref 1 and 2)
                       \s+               # space(s)
                       (\w+)             # a word (backref 3)
                       \s+               # space(s)
                       \S+\s+GB          # non-space(s) ' GB'
                       \s+               # space(s)
                       \d+\s+Gbps        # number(s) ' Gbps'
                       \s+               # space(s)
                       (\S+)             # non-space(s) (backref 4)
                       \s+               # space(s)
                       (\w+)             # a word (backref 5)
                      }xsm)
            # should catch ' 1, 3  Optimal  333.33 GB  6 Gbps  ...'
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'product id' => $4,
                                  'fw' => $5
                              }; }
        elsif ($_ =~ m{^\s+              # line starts with space(s)
                       (\d+),\s+(\d+)    # '##, ##' (backref 1 and 2)
                       \s+               # space(s)
                       (\w+)             # a word (backref 3)
                       \s+               # space(s)
                       \S+\s+GB          # non-space(s) ' GB'
                       \s+               # space(s)
                       \w+               # a word
                       \s+               # space(s)
                       \d+\s+Gbps        # number(s) ' Gbps'
                       \s+               # space(s)
                       (\S+)             # non-space(s) (backref 4)
                       \s+               # space(s)
                       (\w+)             # a word (backref 5)
                      }xsm)
            # should catch ' 1,  3  Optimal  333.33 GB  FCdr  6 Gbps ...'
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'product id' => $4,
                                  'fw' => $5
                              }; }
    }
    elsif($section eq 'hot spares') 
    {
        # if we are in the GHS section
        if ($_ =~ m{
                    # matches 'Total hot spare drives:'
                    Total \s hot \s spare \s drives:
                    \s+      # space(s)
                    (\d+)    # number(s) (backref 1)
                   }xsm)     # should catch 'Total hot spare drives: 1'
        # end the section if there are not GHS drives
        { if ($1 == 0) { $section = ''; } }
        elsif ($_ =~ m{^                    # line starts with
                       \s*                  # optional space(s)
                       # 'Standby drive at '
                       Standby \s drive \s at \s
                       tray \s (\d+), \s    # 'tray ' number(s), (backref 1)
                       slot \s (\d+)        # 'slot ' number(s), (backref 2)
                      }xsm)
            # should catch 'Standby drive at tray 8, slot 16'
        # add any GHS drives to the @hot_spares array
        { $subsection = ''; push(@hot_spares,[$1,$2]); }
        elsif ($_ =~ m{^                    
                       \s*                  
                       In \s use \s drive \s at \s
                       tray \s (\d+), \s    
                       slot \s (\d+)        
                      }xsm)                 
        {
            push(@hot_spares,[$1,$2]);
            $hot_spares_inuse{$1}->{$2} = 1;
            # flag a special subsection for the [tray, slot] in case in use
            $subsection = [$1, $2];
        }
        elsif ($subsection &&
               $_ =~ m{^                    # line starts with
                       \s*                  # optional space(s)
                       # 'Sparing for drive at '
                       Sparing \s for \s drive \s at \s
                       tray \s (\d+), \s    # 'tray ' number(s)', ' (backref 1)
                       slot \s (\d+)        # 'slot ' number(s) (backref 2)
                      }xsm)
            # should catch 'Sparing for drive at tray 4, slot 3'
        # append the location where the GHS is sparing for another drive
        { $hot_spares_inuse{$subsection->[0]}->{$subsection->[1]} = [$1, $2]; }
    }
}
close(SAP);
print "Done.\n";

#-------------------------------------------------------------------------------

# print_controller_information - prints out the controller information
sub print_controller_information
{
    print "\nCONTROLLERS\n\n";
    if ($controllers{'a'}->{'type'} && $controllers{'a'}->{'fw'})
    { printf("These are %s controllers with %s FW.\n\n",
           $controllers{'a'}->{'type'},$controllers{'a'}->{'fw'}); }
    elsif ($controllers{'b'}->{'type'} && $controllers{'b'}->{'fw'})
    { printf("These are %s controllers with %s FW.\n\n",
           $controllers{'b'}->{'type'},$controllers{'b'}->{'fw'}); }
    printf("Controller A (%s) is %s.\n",
        ($controllers{'a'}->{'sn'} ? # check for a SN
         $controllers{'a'}->{'sn'} : # print
         'No SN found'),             # or print not found
        ($controllers{'a'}->{'status'} ? # check for a status
         $controllers{'a'}->{'status'} : # print
         'Unknown'));                    # or print unknown
    printf("Controller B (%s) is %s.\n",
        ($controllers{'b'}->{'sn'} ? # check for a SN
         $controllers{'b'}->{'sn'} : # print
         'No SN found'),             # or print not found
        ($controllers{'b'}->{'status'} ? # check for a status
         $controllers{'b'}->{'status'} : # print
         'Unknown'));                    # or print unknown
    print "\n",'-'x79,"\n";
    return;
}

# max - prints out the maximum of a list of values
sub max
{
    my $max;
    foreach (@_)
    { if (!(defined $max) || $_ > $max) { $max = $_; } }
    return $max;
}

# print_volume_information - prints out the volume information
sub print_volume_information
{
    my @bad_volumes;
    foreach (0 .. max(keys %volumes))
    {
        if ($volumes{$_} &&
            $volumes{$_}->{'status'} ne 'Online' &&
            $volumes{$_}->{'status'} ne 'Optimal')
        { push(@bad_volumes,[$_, $volumes{$_}->{'status'}]); }
    }
    if (@bad_volumes) 
    {
        print "\nNON-OPTIMAL VOLUMES\n\n";
        print "    Volume ",$_->[0]," is ",$_->[1],"\n" foreach(@bad_volumes);
    }
    print "\nVOLUMES\n\n";
    print '/','-'x73,'\\',"\n";
    printf("| %-6s |  %-6s  | %-4s | %-5s | %-5s | %-28s |\n",
           'Volume','Status','RAID','Media','Owner','Drives');
    print '|','='x8,'|','='x10,'|','='x6,'|';
    print '='x7,'|','='x7,'|','='x30,'|',"\n";
    foreach (0 .. max(keys %volumes))
    {
        if (defined $volumes{$_})
        {
            printf("|   %-3s  | %-8s |  %-2s  |  %-3s  |   %1s   | %-28s |\n",
                $_,$volumes{$_}->{'status'},
                $volumes{$_}->{'raid'},
                # for the type, print 'HDD', 'SSD' or 'N/A'
                ($volumes{$_}->{'type'} ? # if there's something recorded...
                 ($volumes{$_}->{'type'} =~ m{Hard}xsm ? 'HDD' : 'SSD') :
                'N/A'),
                $volumes{$_}->{'owner'},
                (scalar @{$volumes{$_}->{'drives'}} != 0 ?
                join('  ',@{$volumes{$_}->{'drives'}}) :
                'ERROR, CHECK FULL PROFILE!'));
           }
    }
    print '\\','-'x73,'/',"\n\n";
    print '-'x79,"\n";
    return;
}

# print_drive_information - prints out the drive information
sub print_drive_information
{
    my @bad_drives;
    for my $tray (0 .. $#drives)
    {
        for my $slot (keys %{$drives[$tray]})
        {
            if ($drives[$tray]->{$slot}->{'status'} ne 'Optimal')
            { push(@bad_drives,
                   [$tray, $slot, $drives[$tray]->{$slot}->{'status'}]);
            }
        }
    }
    if (@bad_drives) 
    {
        print "\nNON-OPTIMAL DRIVES\n\n";
        foreach(@bad_drives)
        {
            print "    Drive at ",$_->[0],',',$_->[1]," is ",$_->[2],".\n";
        }
    }
    print "\nDRIVES\n\n";
    print '/','-'x56,'\\',"\n";
    printf("| %-5s  |   %-6s   | %-5s |  %-2s  | %-17s |\n",
           'Drive','Status','Media','FW','Product ID');
    print '|','='x8,'|','='x12,'|','='x7,'|','='x6,'|','='x19,'|',"\n";
    for my $tray (0 .. $MAXTRAY)
    {
        for my $slot (0 .. $MAXSLOT)
        {
            if($drives[$tray] && $drives[$tray]->{$slot})
            { printf("|  %-4s  | %-10s |  %-3s  | %-4s | %-17s |\n",
                   "$tray,$slot",
                    $drives[$tray]->{$slot}->{'status'},
                    # for drive type print 'HDD', 'SSD', or 'N/A'
                   ($drives[$tray]->{$slot}->{'type'} ?
                     ($drives[$tray]->{$slot}->{'type'} =~ m{Hard}xsm ? 
                     'HDD' : 'SSD' ) : 
                     'N/A'),
                   $drives[$tray]->{$slot}->{'fw'},
                   $drives[$tray]->{$slot}->{'product id'}); }
        }
    }
    print '\\','-'x56,'/',"\n\n";
    print '-'x79,"\n";
    return;
}

# print_hot_spares - prints out the hot spares defined in the disk array
sub print_hot_spares
{
    print "\nGHS DRIVES: ";
    print '(',$_->[0],',',$_->[1],') ' foreach(@hot_spares);
    print "\n\n";
    for my $tray (keys %hot_spares_inuse)
    {
        for my $slot (keys %{$hot_spares_inuse{$tray}})
        {
            print "($tray,$slot) is sparing for (";
            print $hot_spares_inuse{$tray}->{$slot}->[0],',';
            print $hot_spares_inuse{$tray}->{$slot}->[1],")\n";
        }
    }
    if (%hot_spares_inuse) { print "\n"; }
    print '-'x79,"\n";
    return;
}

# print_damc - prints out the name of the disk array in question
sub print_damc
{
    print ' 'x35,$damc,"\n";
    print '-'x79,"\n";
    return;
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";

# only print information we actually have
if ($damc) { print_damc; }
if (%controllers) { print_controller_information; }
if (@hot_spares) { print_hot_spares; }
if (%volumes) { print_volume_information; }
if (@drives) { print_drive_information; }

1;

__END__

#-------------------------------------------------------------------------------

=pod

=for stopwords RCS

=head1 NAME

AnalyzeProfile.pl - Analyzes storageArrayProfile for disk array troubleshooting

=head1 DESCRIPTION

This program parses through the storageArrayProfile of a support bundle. This
quickly parses through the dense information to provide a summary that can
describe the health of the system. Similar to the server management or GUI
in SYMplicity for getting the basic health of the system.

=head1 USAGE

C<perl AnalyzeProfile.pl [-n|-?|-v|storageArrayProfile.txt]>

=head1 OPTIONS

=over 4

=item C<-n>, C<--nohup>

    Run without user input and print to STDOUT

=item C<-v>, C<--version>

    Print version number and exit

=item C<-h>, C<--help>, C<-?>

    Print usage information and exit

=back

=head1 EXIT STATUS

    If the program exited successfully, it will exit with a code of 0.
    All other exit codes indicate an error.

=head1 BUGS AND LIMITATIONS

    This program assumes a maximum of 9 trays and 24 slots.
    Manual alteration is required for anything more specific.

=head1 AUTHOR

Jason Michael Runkle <jason.runkle@teradata.com>

=cut
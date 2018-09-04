###############################################################################
# 
# Developed with Kate
#
#  (c) 2018 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#       - Bernd (Cluni) this module is based on the logic of his script "Rollladensteuerung für HM/ROLLO inkl. Abschattung und Komfortfunktionen in Perl" (https://forum.fhem.de/index.php/topic,73964.0.html)
#       - Beta-User for many tests and ideas
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################





package main;

use strict;
use warnings;




my $version = "0.1.3";


sub AutoShuttersControl_Initialize($) {
    my ($hash) = @_;

## Da ich mit package arbeite müssen in die Initialize für die jeweiligen hash Fn Funktionen der Funktionsname
#  und davor mit :: getrennt der eigentliche package Name des Modules
    $hash->{SetFn}      = "AutoShuttersControl::Set";
    #$hash->{GetFn}      = "ShuttersControl::Get";
    $hash->{DefFn}      = "AutoShuttersControl::Define";
    $hash->{NotifyFn}   = "AutoShuttersControl::Notify";
    $hash->{UndefFn}    = "AutoShuttersControl::Undef";
    $hash->{AttrFn}     = "AutoShuttersControl::Attr";
    $hash->{AttrList}   = "disable:0,1 ".
                            #"disabledForIntervals ".
                            "guestPresence:on,off ".
                            "temperatureSensor ".
                            "temperatureReading ".
                            "brightnessMinVal ".
                            "autoShutterControlMorning:on,off ".
                            "autoShuttersControlEvening:on,off ".
                            "autoShuttersControl_Shading:on,off ".
                            "autoShuttersControlComfort:on,off ".
                            "sunPosDevice ".
                            "sunPosReading ".
                            "sunElevationDevice ".
                            "sunElevationReading ".
                            "presenceDevice ".
                            "presenceReading ".
                            "autoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON ".
                            "autoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 ".
                            "autoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON ".
                            "autoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 ".
                            "antifreezeTemp ".
                            $readingFnAttributes;

## Ist nur damit sich bei einem reload auch die Versionsnummer erneuert.
    foreach my $d(sort keys %{$modules{AutoShuttersControl}{defptr}}) {
        my $hash = $modules{AutoShuttersControl}{defptr}{$d};
        $hash->{VERSION}    = $version;
    }
}



## unserer packagename der Funktion
package AutoShuttersControl;


use strict;
use warnings;
use POSIX;

use GPUtils qw(:all);  # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Data::Dumper;      #only for Debugging
use Date::Parse;

my $missingModul = "";


## Import der FHEM Funktionen
BEGIN {

    GP_Import(qw(
        devspec2array
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBulkUpdateIfChanged
        readingsBeginUpdate
        readingsEndUpdate
        defs
        modules
        Log3
        CommandAttr
        CommandDeleteAttr
        CommandDeleteReading
        CommandSet
        AttrVal
        ReadingsVal
        IsDisabled
        deviceEvents
        init_done
        addToDevAttrList
        addToAttrList
        delFromDevAttrList
        delFromAttrList
        gettimeofday
        sunset_abs
        sunrise_abs
        InternalTimer
        RemoveInternalTimer
        computeAlignTime
    ))
};



## Die Attributsliste welche an die Rolläden verteilt wird. Zusammen mit Default Werten
my %userAttrList =  (   'AutoShuttersControl_Mode_Up:absent,always,off' =>  'always',
                        'AutoShuttersControl_Mode_Down:absent,always,off'   =>  'always',
                        'AutoShuttersControl_Up:time,astro' =>  'astro',
                        'AutoShuttersControl_Down:time,astro'   =>  'astro',
                        'AutoShuttersControl_Open_Pos:0,10,20,30,40,50,60,70,80,90,100'   =>  ['',0,100],
                        'AutoShuttersControl_Closed_Pos:0,10,20,30,40,50,60,70,80,90,100'   =>  ['',100,0],
                        'AutoShuttersControl_Pos_Cmd'   =>  ['','position','pct'],
                        'AutoShuttersControl_Direction' =>  178,
                        'AutoShuttersControl_Time_Up_Early' =>  '04:30:00',
                        'AutoShuttersControl_Time_Up_Late'  =>  '09:00:00',
                        'AutoShuttersControl_Time_Up_WE_Holiday'    =>  '09:30:00',
                        'AutoShuttersControl_Time_Down_Early'   =>  '15:30:00', 
                        'AutoShuttersControl_Time_Down_Late'    =>   '22:30:00',
                        'AutoShuttersControl_Rand_Minutes'  =>  20,
                        'AutoShuttersControl_WindowRec' =>  '',
                        'AutoShuttersControl_Ventilate_Window_Open:on,off'  =>  'on',
                        'AutoShuttersControl_lock-out:on,off'   =>  'off',
                        'AutoShuttersControl_Shading_Pos:10,20,30,40,50,60,70,80,90,100'    =>  30,
                        'AutoShuttersControl_Shading:on,off,delayed,present,absent' =>  'off',
                        'AutoShuttersControl_Shading_Pos_after_Shading:-1,0,10,20,30,40,50,60,70,80,90,100' =>  -1,
                        'AutoShuttersControl_Shading_Angle_Left:0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90' =>  85,
                        'AutoShuttersControl_Shading_Angle_Right:0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90'    =>  85,
                        'AutoShuttersControl_Shading_Brightness_Sensor' =>  '',
                        'AutoShuttersControl_Shading_Brightness_Reading'    =>  'brightness',
                        'AutoShuttersControl_Shading_StateChange_Sunny'     =>  '6000',
                        'AutoShuttersControl_Shading_StateChange_Cloudy'    =>  '4000',
                        'AutoShuttersControl_Shading_WaitingPeriod' =>  20,
                        'AutoShuttersControl_Shading_Min_Elevation' =>  '',
                        'AutoShuttersControl_Shading_Min_OutsideTemperature'    =>  18,
                        'AutoShuttersControl_Shading_BlockingTime_After_Manual' =>  20,
                        'AutoShuttersControl_Shading_BlockingTime_Twilight'     => 45,
                        'AutoShuttersControl_Shading_Fast_Open:on,off'  =>  '',
                        'AutoShuttersControl_Shading_Fast_Close:on,off' =>  '',
                        'AutoShuttersControl_Offset_Minutes_Morning'    =>  1,
                        'AutoShuttersControl_Offset_Minutes_Evening'    =>  1,
                        'AutoShuttersControl_WindowRec_subType:twostate,threestate' =>  'twostate',
                        'AutoShuttersControl_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'  =>  ['',70,30],
                        'AutoShuttersControl_GuestRoom:on,off'  =>  '',
                        'AutoShuttersControl_Pos_after_ComfortOpen:-2,-1,0,10,20,30,40,50,60,70,80,90,100'  =>  '',
                        'AutoShuttersControl_Antifreeze:off,morning'    =>  'off',
                        'AutoShuttersControl_Partymode:on,off'  =>  'off',
                        'AutoShuttersControl_Roommate_Device'   =>  '',
                        'AutoShuttersControl_Roommate_Reading'   =>  'state',
                    );





sub Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "only one AutoShuttersControl instance allowed" if( devspec2array('TYPE=AutoShuttersControl') > 1 ); # es wird geprüft ob bereits eine Instanz unseres Modules existiert, wenn ja wird abgebrochen
    #return "too few parameters: define <name> ShuttersControl <Shutters1 Shutters2 ...> or <auto>" if( @a < 3 );    # es dürfen nicht weniger wie 3 Optionen unserem define mitgegeben werden
    return "too few parameters: define <name> ShuttersControl <Shutters1 Shutters2 ...> or <auto>" if( @a < 2 );
    return "Cannot define ShuttersControl device. Perl modul ${missingModul}is missing." if ( $missingModul );  # Abbruch wenn benötigte Hilfsmodule nicht vorhanden sind / vorerst unwichtig
    

    my $name                    = $a[0];

    $hash->{VERSION}            = $version;
    $hash->{MID}                = 'da39a3ee5e6b4b0d3255bfef95601890afd80709';   # eine Ein Eindeutige ID für interne FHEM Belange / nicht weiter wichtig
    $hash->{NotifyOrderPrefix}  = "51-";                                        # Order Nummer für NotifyFn
    $hash->{NOTIFYDEV}          = "global,".$name;                              # Liste aller Devices auf deren Events gehört werden sollen
    

    readingsSingleUpdate($hash,"state","please set attribut 'AutoShuttersControl' with value 1 to all your auto controled shutters and and then do 'set DEVICENAME scanForShutters", 1);
    CommandAttr(undef,$name . ' room AutoShuttersControl') if( AttrVal($name,'room','none') eq 'none' );
    CommandAttr(undef,$name . ' autoAstroModeEvening REAL') if( AttrVal($name,'autoAstroModeEvening','none') eq 'none' );
    CommandAttr(undef,$name . ' autoAstroModeMorning REAL') if( AttrVal($name,'autoAstroModeMorning','none') eq 'none' );
    CommandAttr(undef,$name . ' autoShutterControlMorning on') if( AttrVal($name,'autoShutterControlMorning','none') eq 'none' );
    CommandAttr(undef,$name . ' autoShuttersControlEvening on') if( AttrVal($name,'autoShuttersControlEvening','none') eq 'none' );
    
    addToAttrList('AutoShuttersControl:0,1,2');
    
    Log3 $name, 3, "AutoShuttersControl ($name) - defined";
    
    $modules{AutoShuttersControl}{defptr}{$hash->{MID}} = $hash;
    
    return undef;
}

sub Undef($$) {

    my ($hash,$arg) = @_;
    
    
    my $name = $hash->{NAME};
    
    UserAttributs_Readings_ForShutters($hash,'del');          # es sollen alle Attribute und Readings in den Rolläden Devices gelöscht werden welche vom Modul angelegt wurden
    delFromAttrList('AutoShuttersControl:0,1,2');
    
    delete($modules{AutoShuttersControl}{defptr}{$hash->{MID}});
    
    Log3 $name, 3, "AutoShuttersControl ($name) - delete device $name";
    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            #RemoveInternalTimer($hash);
            
            #readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "AutoShuttersControl ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "AutoShuttersControl ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "AutoShuttersControl ($name) - disabledForIntervals";
            #readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        }
        
        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "AutoShuttersControl ($name) - enabled";
            #readingsSingleUpdate ( $hash, "state", "active", 1 );
        }
    }
    
    return undef;
}

sub Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));

    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);

    Log3 $name, 5, "AutoShuttersControl ($name) - Devname: ".$devname." Name: ".$name." Notify: ".Dumper $events;       # mit Dumper


    if( (grep /^DEFINED.$name$/,@{$events}
        and $devname eq 'global'
        and $init_done)
        or (grep /^INITIALIZED$/,@{$events}
        or grep /^REREADCFG$/,@{$events}
        or grep /^MODIFIED.$name$/,@{$events})
        and $devname eq 'global') {

            ## Ist der Event ein globaler und passt zum Rest der Abfrage oben wird nach neuen Rolläden Devices gescannt und eine Liste im Rolladenmodul sortiert nach Raum generiert
            readingsSingleUpdate($hash,'partyMode','off',0) if(ReadingsVal($name,'partyMode','none') eq 'none');
            
            ShuttersDeviceScan($hash)
            unless( ReadingsVal($name,'userAttrList','none') eq 'none');
    
    } 
    
    return unless( ref($hash->{helper}{shuttersList}) eq 'ARRAY' and scalar(@{$hash->{helper}{shuttersList}}) > 0);
    
    if( $devname eq $name ) {
        if( grep /^userAttrList:.rolled.out$/,@{$events} ) {
            unless( scalar(@{$hash->{helper}{shuttersList}} ) == 0 ) {
                WriteReadingsShuttersList($hash);
                UserAttributs_Readings_ForShutters($hash,'add');
                InternalTimer(gettimeofday() + 5,'AutoShuttersControl::RenewSunRiseSetShuttersTimer',$hash);
            }
            
        } elsif( grep /^partyMode:.off$/,@{$events} ) {
            PartyModeEventProcessing($hash);
        }

    } elsif( $devname eq "global" ) {           # Kommt ein globales Event und beinhaltet folgende Syntax wird die Funktion zur Verarbeitung aufgerufen
        if (grep /^(ATTR|DELETEATTR)\s(.*AutoShuttersControl_Roommate_Device|.*AutoShuttersControl_WindowRec)(\s.*|$)/,@{$events}) {
            GeneralEventProcessing($hash,undef,join(' ',@{$events}));
        }
        
    } else {
        GeneralEventProcessing($hash,$devname,join(' ',@{$events}));            # bei allen anderen Events wird die entsprechende Funktion zur Verarbeitung aufgerufen
    }

    return;
}

sub GeneralEventProcessing($$$) {

    my ($hash,$devname,$events)  = @_;
    my $name            = $hash->{NAME};


    if( defined($devname) and ($devname) ) {                # es wird lediglich der Devicename der Funktion mitgegeben wenn es sich nicht um global handelt daher hier die Unterschiedung
    
        my ($notifyDevHash)    = ExtractNotifyDevfromReadingString($hash,$devname);     # da wir nicht wissen im welchen Zusammenhang das Device, welches das Event ausgelöst hat, mit unseren Attributen steht lesen wir ein spezielles Reading aus dessen Wert einen bestimmten Aufbau hat und uns sagen kann ob es ein Fenster oder ein Bewohner oder sonst was für ein Device ist.
        Log3 $name, 4, "AutoShuttersControl ($name) - EventProcessing: " . $notifyDevHash->{$devname};
        
        foreach(@{$notifyDevHash->{$devname}}) {        # Wir lesen nun alle Einträge aus welche dieses Device betreffen. Kann ja mehrere Rolläden betreffen.

            WindowRecEventProcessing($hash,(split(':',$_))[0],$events) if( (split(':',$_))[1] eq 'AutoShuttersControl_WindowRec' );     # ist es ein Fensterdevice wird die Funktion gestartet
            RoommateEventProcessing($hash,(split(':',$_))[0],$events) if( (split(':',$_))[1] eq 'AutoShuttersControl_Roommate_Device' );    # ist es ein Bewohner Device wird diese Funktion gestartet
        
        
        
            Log3 $name, 4, "AutoShuttersControl ($name) - EventProcessing Hash Array: " . $_;
        }
    } else {        # alles was kein Devicenamen mit übergeben hat landet hier

        if( $events =~ m#^ATTR\s(.*)\s(AutoShuttersControl_Roommate_Device|AutoShuttersControl_WindowRec)\s(.*)$# ) {       # wurde den Attributen unserer Rolläden ein Wert zugewiesen ?
            AddNotifyDev($hash,$3,$1 . ':' . $2 . ':' . $3);
            Log3 $name, 4, "AutoShuttersControl ($name) - EventProcessing: ATTR";
        } elsif($events =~ m#^DELETEATTR\s(.*AutoShuttersControl_Roommate_Device|.*AutoShuttersControl_WindowRec)$# ) {      # wurde das Attribut unserer Rolläden gelöscht ?
            Log3 $name, 4, "AutoShuttersControl ($name) - EventProcessing: DELETEATTR";
            DeleteNotifyDev($hash,$1);
        }
    }
}

sub Set($$@) {
    
    my ($hash, $name, @aa)  = @_;
    
    
    my ($cmd, @args)        = @aa;

    if( lc $cmd eq 'renewsetsunrisesunsettimer' ) {
        return "usage: $cmd" if( @args != 0 );
        RenewSunRiseSetShuttersTimer($hash);
        
    } elsif( lc $cmd eq 'scanforshutters' ) {
        return "usage: $cmd" if( @args != 0 );
        
        ShuttersDeviceScan($hash);
        
    } elsif( lc $cmd eq 'partymode' ) {
        return "usage: $cmd" if( @args > 1 );
        
        readingsSingleUpdate ($hash, "partyMode", join(' ',@args), 1);
    
    } else {
        my $list = "scanForShutters:noArg";
        $list .= " renewSetSunriseSunsetTimer:noArg partyMode:on,off" if( ReadingsVal($name,'userAttrList',0) eq 'rolled out');
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub ShuttersDeviceScan($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    my @list;
    @list = devspec2array('AutoShuttersControl=[1-2]');
    
    delete $hash->{helper}{shuttersList};

    unless( scalar(@list) > 0 ) {
        CommandDeleteReading(undef,$name . ' room_.*');
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,'userAttrList','none');
        readingsBulkUpdate($hash,'state','no shutters found');
        readingsEndUpdate($hash,1);
        return;
    }
    
    foreach(@list) {
        push (@{$hash->{helper}{shuttersList}},$_);             ## einem Hash wird ein Array zugewiesen welches die Liste der erkannten Rollos beinhaltet
        #AddNotifyDev($hash,$_);        # Vorerst keine Shutters in NOTIFYDEV
        Log3 $name, 4, "AutoShuttersControl ($name) - ShuttersList: " . $_;
    }
    

    if( ReadingsVal($name,'.monitoredDevs','none') ne 'none' ) {             # Dieses besondere Reading ist so aufgebaut das egal wie der Devicename bei einem Event lautet dieses Device nach seiner Funktionalität in FHEM zugeordnet werden kann

        # Der Aufbau des Strings im Reading monitoredDevs sieht so aus Rolloname:Attributname:Wert_desAttributes
        # Wert des Attributes beinhaltet in diesem Fall immer den Devcenamen von dem auch Events von unserem Modul getriggert werden sollen.
        my ($notifyDevHash)    = ExtractNotifyDevfromReadingString($hash,undef);        # in der Funktion wird aus dem String ein Hash wo wir über den Devicenamen z.B. FensterLinks ganz einfach den Rest des Strings heraus bekommen. Also welches Rollo und welches Attribut. So wissen wir das es sich um ein Fenster handelt und dem Rollo bla bla zu geordnet wird.
        my $notifyDevString = "";
        
        while( my  (undef,$notifyDev) = each %{$notifyDevHash}) {
            $notifyDevString .= ',' . $notifyDev unless( $notifyDevString =~ /$notifyDev/ );
            #Log3 $name, 2, "AutoShuttersControl ($name) - NotifyDev: " . $notifyDev . ", NotifyDevString: " . $notifyDevString;
        }

        $hash->{NOTIFYDEV}  = $hash->{NOTIFYDEV} . $notifyDevString;
    }

    
    readingsSingleUpdate($hash,'userAttrList','rolled out',1);
}

## Die Funktion schreibt in das Moduldevice Readings welche Rolläden in welchen Räumen erfasst wurden.
sub WriteReadingsShuttersList($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};


    CommandDeleteReading(undef,$name . ' room_.*');
    
    readingsBeginUpdate($hash);
    
    foreach (@{$hash->{helper}{shuttersList}}) {
    
        readingsBulkUpdate($hash,'room_' . AttrVal($_,'room','unsorted'),ReadingsVal($name,'room_' . AttrVal($_,'room','unsorted'),'') . ', ' . $_) if( ReadingsVal($name,'room_' . AttrVal($_,'room','unsorted'),'none') ne 'none' );
        
        readingsBulkUpdate($hash,'room_' . AttrVal($_,'room','unsorted'),$_) if( ReadingsVal($name,'room_' . AttrVal($_,'room','unsorted'),'none') eq 'none' );
    }
    
    readingsBulkUpdate($hash,'state','active');
    readingsEndUpdate($hash,0);
}

sub UserAttributs_Readings_ForShutters($$) {

    my ($hash,$cmd) = @_;
    my $name        = $hash->{NAME};

    
    while( my ($attrib,$attribValue) = each %{userAttrList} ) {
        foreach (@{$hash->{helper}{shuttersList}}) {

            addToDevAttrList($_,$attrib);       ## fhem.pl bietet eine Funktion um ein userAttr Attribut zu befüllen. Wir schreiben also in den Attribut userAttr alle unsere Attribute rein. Pro Rolladen immer ein Attribut pro Durchlauf
            
            ## Danach werden die Attribute die im userAttr stehen gesetzt und mit default Werten befüllt
            if( $cmd eq 'add' ) {
                if( ref($attribValue) ne 'ARRAY' ) {
                    CommandAttr(undef,$_ . ' ' . (split(':',$attrib))[0] . ' ' . $attribValue) if( defined($attribValue) and $attribValue and AttrVal($_,(split(':',$attrib))[0],'none') eq 'none' );
                } else {
                    CommandAttr(undef,$_ . ' ' . (split(':',$attrib))[0] . ' ' . $attribValue->[AttrVal($_,'AutoShuttersControl',2)]) if( defined($attribValue) and $attribValue and AttrVal($_,(split(':',$attrib))[0],'none') eq 'none' );
                }
            ## Oder das Attribut wird wieder gelöscht.
            } elsif( $cmd eq 'del' ) {
                RemoveInternalTimer(ReadingsVal($_,'.AutoShuttersControl_InternalTimerFuncHash',0));
                CommandDeleteReading(undef,$_ . ' \.?AutoShuttersControl_.*' );
                CommandDeleteAttr(undef,$_ . ' AutoShuttersControl');
                delFromDevAttrList($_,$attrib);         # Funktion in fhem.pl die ich Rudi als Patch eingereicht habe, hoffe wird angenommen
            }
        }
    }
}

## Fügt dem NOTIFYDEV Hash weitere Devices hinzu
sub AddNotifyDev($@) {

    my ($hash,$dev,$readingPart)    = @_;
    
    my $name                        = $hash->{NAME};
    my $readingPart3                = (split(':', $readingPart))[2];


    my $notifyDev                   = $hash->{NOTIFYDEV};
    $notifyDev                      = "" if(!$notifyDev);
    my %hash;
    
    %hash = map { ($_ => 1) }
            split(",", "$notifyDev,$readingPart3");
                
    $hash->{NOTIFYDEV}              = join(",", sort keys %hash);

    
    my $monitoredDevString          = ReadingsVal($name,'.monitoredDevs','');
    %hash = map { ($_ => 1) }
            split(",", "$monitoredDevString,$readingPart");
    readingsSingleUpdate($hash,'.monitoredDevs',(ReadingsVal($name,'.monitoredDevs','none') eq 'none' ? join("", sort keys %hash) : join(",", sort keys %hash)),0);
}

## entfernt aus dem NOTIFYDEV Hash Devices welche als Wert in Attributen steckten
sub DeleteNotifyDev($$) {

    my ($hash,$dev)     = @_;

    my $name    = $hash->{NAME};
    $dev =~ s/\s/:/g;


    my ($notifyDevHash)             = ExtractNotifyDevfromReadingString($hash,undef);
    my $devFromDevHash              = $notifyDevHash->{$dev};
    
    ##### Entfernen des gesamten Device Stringes vom Reading monitoredDevs
    my $monitoredDevString          = ReadingsVal($name,'.monitoredDevs','none');
    my $devStringAndDevFromDevHash  = $dev . ':' . $devFromDevHash;
    my %hash;
    
    %hash = map { ($_ => 1) }
            grep { " $devStringAndDevFromDevHash " !~ m/ $_ / }
            split(",", "$monitoredDevString,$devStringAndDevFromDevHash");

    readingsSingleUpdate($hash,'.monitoredDevs',join(",", sort keys %hash),0);
    
    
    ### Entfernen des Deviceeintrages aus dem NOTIFYDEV
    unless( ReadingsVal($name,'.monitoredDevs','none') =~ m#$devFromDevHash# ) {

        my $notifyDevString             = $hash->{NOTIFYDEV};
        $notifyDevString                = "" if(!$notifyDevString);

        %hash = map { ($_ => 1) }
                grep { " $devFromDevHash " !~ m/ $_ / }
                split(",", "$notifyDevString,$devFromDevHash");
                    
        $hash->{NOTIFYDEV}              = join(",", sort keys %hash);
    }
}

## Sub zum steuern der Rolläden bei einem Fenster Event
sub WindowRecEventProcessing($@) {

    my ($hash,$shuttersDev,$events)    = @_;
    
    my $name                           = $hash->{NAME};


    if($events =~ m#state:\s(open|closed|tilted)# ) {
        my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
        my $queryShuttersPosWinRecTilted                = (ShuttersPosCmdValueNegieren($shuttersDev) ? ReadingsVal($shuttersDev,AttrVal($shuttersDev,'AutoShuttersControl_Pos_Cmd','pct'),0) > $closedPosWinRecTilted : ReadingsVal($shuttersDev,AttrVal($shuttersDev,'AutoShuttersControl_Pos_Cmd','pct'),0) < $closedPosWinRecTilted);
        
        if(ReadingsVal($shuttersDev,'.AutoShuttersControl_DelayCmd','none') ne 'none') {                # Es wird geschaut ob wärend der Fenster offen Phase ein Fahrbefehl über das Modul kam, wenn ja wird dieser aus geführt
            my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
            
            ### Es wird ausgewertet ob ein normaler Fensterkontakt oder ein Drehgriff vorhanden ist. Beim normalen Fensterkontakt bedeutet ein open das selbe wie tilted beim Drehgriffkontakt.
            if( $1 eq 'closed' ) {
                ShuttersCommandSet($hash,$shuttersDev,ReadingsVal($shuttersDev,'.AutoShuttersControl_DelayCmd',0));

            } elsif( ($1 eq 'tilted' or ($1 eq 'open' and AttrVal($shuttersDev,'AutoShuttersControl_WindowRec_subType','twostate') eq 'twostate')) and AttrVal($shuttersDev,'AutoShuttersControl_Ventilate_Window_Open','off') eq 'on' and $queryShuttersPosWinRecTilted ) {
                ShuttersCommandSet($hash,$shuttersDev,$closedPosWinRecTilted);
            }
        } elsif( $1 eq 'closed' ) {             # wenn nicht dann wird entsprechend dem Fensterkontakt Event der Rolladen geschlossen oder zum lüften geöffnet
            ShuttersCommandSet($hash,$shuttersDev,$closedPos) if(ReadingsVal($shuttersDev,AttrVal($shuttersDev,'AutoShuttersControl_Pos_Cmd','pct'),0) == $closedPosWinRecTilted);
        
        } elsif( ($1 eq 'tilted' or ($1 eq 'open' and AttrVal($shuttersDev,'AutoShuttersControl_WindowRec_subType','twostate') eq 'twostate')) and AttrVal($shuttersDev,'AutoShuttersControl_Ventilate_Window_Open','off') eq 'on' and $queryShuttersPosWinRecTilted ) {
            ShuttersCommandSet($hash,$shuttersDev,$closedPosWinRecTilted);
        }
    }
}

## Sub zum steuern der Rolladen bei einem Bewohner/Roommate Event
sub RoommateEventProcessing($@) {

    my ($hash,$shuttersDev,$events) = @_;
    
    my $name                        = $hash->{NAME};
    my $reading                     = AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Reading','state');

    
    if($events =~ m#$reading:\s(gotosleep|asleep|awoken|home)# ) {
    
        my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
        
    
        Log3 $name, 4, "AutoShuttersControl ($name) - RoommateEventProcessing: $reading";
        Log3 $name, 4, "AutoShuttersControl ($name) - RoommateEventProcessing: $shuttersDev und Events $events";


        if( AttrVal($shuttersDev,'AutoShuttersControl_Mode_Up','off') eq 'always' ) {
            ShuttersCommandSet($hash,$shuttersDev,$openPos)
            if( ($1 eq 'home' or $1 eq 'awoken') and (ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),'lastState','none') eq 'asleep' or ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),'lastState','none') eq 'awoken') and AttrVal($name,'autoShutterControlMorning','off') eq 'on' and IsDay($hash,$shuttersDev) );
        }

         if( AttrVal($shuttersDev,'AutoShuttersControl_Mode_Down','off') eq 'always' ) {
            if( CheckIfShuttersWindowRecOpen($shuttersDev) == 2 and AttrVal($shuttersDev,'AutoShuttersControl_WindowRec_subType','twostate') eq 'threestate') {
                Log3 $name, 4, "AutoShuttersControl ($name) - RoommateEventProcessing Fenster offen";
                ShuttersCommandDelaySet($shuttersDev,$closedPos);
                Log3 $name, 4, "AutoShuttersControl ($name) - RoommateEventProcessing - Spring in ShuttersCommandDelaySet";
            } else {
                Log3 $name, 4, "AutoShuttersControl ($name) - RoommateEventProcessing Fenster nicht offen";
                ShuttersCommandSet($hash,$shuttersDev,(CheckIfShuttersWindowRecOpen($shuttersDev) == 0 ? $closedPos : $closedPosWinRecTilted))
                if( ($1 eq 'gotosleep' or $1 eq 'asleep') and AttrVal($name,'autoShuttersControlEvening','off') eq 'on' );
            }
        }
    }
}

sub PartyModeEventProcessing($) {

    my ($hash)  = @_;
    
    my $name            = $hash->{NAME};


    foreach my $shuttersDev (@{$hash->{helper}{shuttersList}}) {
        my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
        
        if( CheckIfShuttersWindowRecOpen($shuttersDev) == 2 and AttrVal($shuttersDev,'AutoShuttersControl_WindowRec_subType','twostate') eq 'threestate') {
            Log3 $name, 4, "AutoShuttersControl ($name) - PartyModeEventProcessing Fenster offen";
            ShuttersCommandDelaySet($shuttersDev,$closedPos);
            Log3 $name, 4, "AutoShuttersControl ($name) - PartyModeEventProcessing - Spring in ShuttersCommandDelaySet";
        } else {
            Log3 $name, 4, "AutoShuttersControl ($name) - PartyModeEventProcessing Fenster nicht offen";
            ShuttersCommandSet($hash,$shuttersDev,(CheckIfShuttersWindowRecOpen($shuttersDev) == 0 ? $closedPos : $closedPosWinRecTilted));
        }
    }
}

# Sub für das Zusammensetzen der Rolläden Steuerbefehle
sub ShuttersCommandSet($$$) {

    my ($hash,$shuttersDev,$posValue)   = @_;


    if(AttrVal($shuttersDev,'AutoShuttersControl_Partymode','off') eq 'on' and ReadingsVal($hash->{NAME},'partyMode','off') eq 'on' ) {
        ShuttersCommandDelaySet($shuttersDev,$posValue);
        
    } else {
        my $posCmd   = AttrVal($shuttersDev,'AutoShuttersControl_Pos_Cmd','pct');
        
        CommandSet(undef,$shuttersDev . ':FILTER=' . $posCmd . '!=' . $posValue . ' ' . $posCmd . ' ' . $posValue);
        readingsSingleUpdate($defs{$shuttersDev},'.AutoShuttersControl_DelayCmd','none',0) if(ReadingsVal($shuttersDev,'.AutoShuttersControl_DelayCmd','none') ne 'none');    # setzt den Wert des Readings auf none da der Rolladen nun gesteuert werden kann. Dieses Reading setzt die Delay Funktion ShuttersCommandDelaySet 
    }
}

# Sub zum späteren ausführen der Steuerbefehle für Rolläden, zum Beispiel weil Fenster noch auf ist
sub ShuttersCommandDelaySet($$) {

    my ($shuttersDev,$posValue)   = @_;

    readingsSingleUpdate($defs{$shuttersDev},'.AutoShuttersControl_DelayCmd',$posValue,0);
}

## Sub welche die InternalTimer nach entsprechenden Sunset oder Sunrise zusammen stellt
sub CreateSunRiseSetShuttersTimer($$) {

    my ($hash,$shuttersDev)             = @_;


    my $name                            = $hash->{NAME};
    
    return if( IsDisabled($name) );


    ## In jedem Rolladen werden die errechneten Zeiten hinterlegt, es sei denn das autoShuttersControlEvening/Morning auf off steht
    readingsBeginUpdate($defs{$shuttersDev});
    
    readingsBulkUpdate( $defs{$shuttersDev},'AutoShuttersControl_Time_Sunset',(AttrVal($name,'autoShuttersControlEvening','off') eq 'on' ? ShuttersSunset($hash,$shuttersDev,'real') : 'AutoShuttersControl off') );
    readingsBulkUpdate($defs{$shuttersDev},'AutoShuttersControl_Time_Sunrise',(AttrVal($name,'autoShutterControlMorning','off') eq 'on' ? ShuttersSunrise($hash,$shuttersDev,'real') : 'AutoShuttersControl off') );
    
    readingsEndUpdate($defs{$shuttersDev},0);


    RemoveInternalTimer(ReadingsVal($shuttersDev,'.AutoShuttersControl_InternalTimerFuncHash',0));
    ## kleine Hilfe für InternalTimer damit ich alle benötigten Variablen an die Funktion übergeben kann welche von Internal Timer aufgerufen wird.
    my %funcHash = ( hash => $hash, shuttersdevice => $shuttersDev);

    ## Ich brauche beim löschen des InternalTimer den Hash welchen ich mitgegeben habe, dieser muss gesichert werden
    readingsSingleUpdate($defs{$shuttersDev},'.AutoShuttersControl_InternalTimerFuncHash',\%funcHash,0);

    InternalTimer(ShuttersSunset($hash,$shuttersDev,'unix'), 'AutoShuttersControl::SunSetShuttersAfterTimerFn',\%funcHash ) if( AttrVal($name,'autoShuttersControlEvening','off') eq 'on' );
    InternalTimer(ShuttersSunrise($hash,$shuttersDev,'unix'), 'AutoShuttersControl::SunRiseShuttersAfterTimerFn',\%funcHash ) if( AttrVal($name,'autoShutterControlMorning','off') eq 'on' );
}

## Funktion zum neu setzen der Timer und der Readings für Sunset/Rise
sub RenewSunRiseSetShuttersTimer($) {

    my $hash    = shift;

    foreach (@{$hash->{helper}{shuttersList}}) {
        CreateSunRiseSetShuttersTimer($hash,$_);
    }
}

## Funktion welche beim Ablaufen des Timers für Sunset aufgerufen werden soll
sub SunSetShuttersAfterTimerFn($) {

    my $funcHash                                    = shift;
    my $hash                                        = $funcHash->{hash};
    my $shuttersDev                                 = $funcHash->{shuttersdevice};
    
    
    my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
    
    if( AttrVal($shuttersDev,'AutoShuttersControl_Mode_Down','off') eq ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Reading','none'),'home') or AttrVal($shuttersDev,'AutoShuttersControl_Mode_Down','off') eq 'always' ) {
        if( CheckIfShuttersWindowRecOpen($shuttersDev) == 2 ) {

            ShuttersCommandDelaySet($shuttersDev,$closedPos);
        } else {
            
            ShuttersCommandSet($hash,$shuttersDev,(CheckIfShuttersWindowRecOpen($shuttersDev) == 0 ? $closedPos : $closedPosWinRecTilted));
        }
    }
    
    CreateSunRiseSetShuttersTimer($hash,$shuttersDev);
}

## Funktion welche beim Ablaufen des Timers für Sunrise aufgerufen werden soll
sub SunRiseShuttersAfterTimerFn($) {

    my $funcHash                                    = shift;
    my $hash                                        = $funcHash->{hash};
    my $shuttersDev                                 = $funcHash->{shuttersdevice};
    
    
    my ($openPos,$closedPos,$closedPosWinRecTilted) = ShuttersReadAttrForShuttersControl($shuttersDev);
    
    if( AttrVal($shuttersDev,'AutoShuttersControl_Mode_Up','off') eq ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Reading','none'),'home') or AttrVal($shuttersDev,'AutoShuttersControl_Mode_Up','off') eq 'always' ) {
        ShuttersCommandSet($hash,$shuttersDev,$openPos) if( ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Reading','none'),'home') eq 'home' or ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Device','none'),AttrVal($shuttersDev,'AutoShuttersControl_Roommate_Reading','none'),'awoken') eq 'awoken' );
    }
    
    CreateSunRiseSetShuttersTimer($hash,$shuttersDev);
}









#################################
## my little helper
#################################

# Hilfsfunktion welche meinen ReadingString zum finden der getriggerten Devices und der Zurdnung was das Device überhaupt ist und zu welchen Rolladen es gehört aus liest und das Device extraiert
sub ExtractNotifyDevfromReadingString($$) {

    my ($hash,$dev) = @_;


    my %notifyDevString;
    
    my @notifyDev = split(',',ReadingsVal($hash->{NAME},'.monitoredDevs','none'));

    if( defined($dev) ) {
        foreach my $notifyDev (@notifyDev) {
            Log3 $hash->{NAME}, 4, "AutoShuttersControl ($hash->{NAME}) - ExtractNotifyDevfromReadingString: " . (split(':',$notifyDev))[2].'-'.(split(':',$notifyDev))[0].':'.(split(':',$notifyDev))[1];
            $notifyDevString{(split(':',$notifyDev))[2]}    = [] unless( ref($notifyDevString{(split(':',$notifyDev))[2]}) eq "ARRAY" );
            push (@{$notifyDevString{(split(':',$notifyDev))[2]}},(split(':',$notifyDev))[0].':'.(split(':',$notifyDev))[1]) unless( $dev ne (split(':',$notifyDev))[2] );
        }

    } else {
        foreach my $notifyDev (@notifyDev) {
            $notifyDevString{(split(':',$notifyDev))[0].':'.(split(':',$notifyDev))[1]}    = (split(':',$notifyDev))[2];
        }
    }

    return \%notifyDevString;
}

## Attribute aud den Rolladen auslesen welche zum Steuern des Rolladen wichtig sind
sub ShuttersReadAttrForShuttersControl($) {

    my $shuttersDev                      = shift;
    
    my $shuttersOpenValue               = AttrVal($shuttersDev,'AutoShuttersControl_Open_Pos',0);
    my $shuttersClosedValue             = AttrVal($shuttersDev,'AutoShuttersControl_Closed_Pos',100);
    my $shuttersClosedByWindowRecTilted = AttrVal($shuttersDev,'AutoShuttersControl_Ventilate_Pos',80);

    return ($shuttersOpenValue,$shuttersClosedValue,$shuttersClosedByWindowRecTilted);
}

## Ist Tag oder Nacht für den entsprechende Rolladen
sub IsDay($$) {

    my ($hash,$shuttersDev) = @_;
    
    my $name                = $hash->{NAME};


    return (ShuttersSunrise($hash,$shuttersDev,'unix') > ShuttersSunset($hash,$shuttersDev,'unix') ? 1 : 0);
}

sub ShuttersSunrise($$$) {

    my ($hash,$shuttersDev,$tm) = @_;       # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
    
    my $name                    = $hash->{NAME};
    my $autoAstroMode           = AttrVal($name,'autoAstroModeMorning','REAL');
    $autoAstroMode              = $autoAstroMode . '=' . AttrVal($name,'autoAstroModeMorningHorizon',0) if( $autoAstroMode eq 'HORIZON' );


    if( $tm eq 'unix' ) {
        return computeAlignTime('24:00',sunrise_abs($autoAstroMode,0,AttrVal($shuttersDev,'AutoShuttersControl_Time_Up_Early','04:30:00'),AttrVal($shuttersDev,'AutoShuttersControl_Time_Up_Late','09:00:00')));
        
    } elsif( $tm eq 'real' ) {
        return sunrise_abs($autoAstroMode,0,AttrVal($shuttersDev,'AutoShuttersControl_Time_Up_Early','04:30:00'),AttrVal($shuttersDev,'AutoShuttersControl_Time_Up_Late','09:00:00'));
    }
}

sub ShuttersSunset($$@) {

    my ($hash,$shuttersDev,$tm) = @_;       # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
    
    my $name                    = $hash->{NAME};
    my $autoAstroMode           = AttrVal($name,'autoAstroModeEvening','REAL');
    $autoAstroMode              = $autoAstroMode . '=' . AttrVal($name,'autoAstroModeEveningHorizon',0) if( $autoAstroMode eq 'HORIZON' );


    if( $tm eq 'unix' ) {
        return computeAlignTime('24:00',sunset_abs($autoAstroMode,0,AttrVal($shuttersDev,'AutoShuttersControl_Time_Down_Early','15:30:00'),AttrVal($shuttersDev,'AutoShuttersControl_Time_Down_Late','22:30:00')));
        
    } elsif( $tm eq 'real' ) {
        return sunset_abs($autoAstroMode,0,AttrVal($shuttersDev,'AutoShuttersControl_Time_Down_Early','15:30:00'),AttrVal($shuttersDev,'AutoShuttersControl_Time_Down_Late','22:30:00'));
    }
}



## Kontrolliert ob das Fenster von einem bestimmten Rolladen offen ist
sub CheckIfShuttersWindowRecOpen($) {

    my $shuttersDev = shift;


    if( ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_WindowRec','none'),'state','closed') eq 'open' ) {
        return 2;
    } elsif( ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_WindowRec','none'),'state','closed') eq 'tilted' and AttrVal($shuttersDev,'AutoShuttersControl_WindowRec_subType','twostate') eq 'threestate') {
        return 1;
    } elsif( ReadingsVal(AttrVal($shuttersDev,'AutoShuttersControl_WindowRec','none'),'state','closed') eq 'closed' ) {
        return 0;
    }
}

sub ShuttersPosCmdValueNegieren($) {

    my $shuttersDev     = shift;
    
    return (AttrVal($shuttersDev,'AutoShuttersControl_Open_Pos',0) < AttrVal($shuttersDev,'AutoShuttersControl_Closed_Pos',100) ? 1 : 0);
}







1;




=pod
=item device
=item summary       Modul 
=item summary_DE    Modul zur Automatischen Rolladensteuerung auf Basis bestimmter Ereignisse

=begin html

<a name="AutoShuttersControl"></a>
<h3>Auto Shutters Control</h3>
<ul>
  
</ul>

=end html

=begin html_DE

<a name="AutoShuttersControl"></a>
<h3>Automatische Rolladensteuerung</h3>
<ul>
  <u><b>AutoShuttersControl - Steuert automatisch Deine Rolladen nach bestimmten Vorgaben. Zum Beispiel Sonnenaufgang und Sonnenuntergang</b></u>
  <br>
  
</ul>

=end html_DE

=cut

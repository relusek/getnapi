#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use LWP::Simple;
use File::Find;
use Encode qw( from_to );
use Data::Dumper;
use Getopt::Long;

#==========MAIN PROGRAM
#media filter
my $filter = "(avi|wmv|mkv|rmvb|3gp|mp4|mpe?g)";
#config
my $Conf = {
    utf         => 0,
    makesrt => 1,
    removetxt => 0, 
    force   => 0, 
    debug   => 0,
    test        => 0,   
    saveconfig  => 0,
    once  => 0,
    cover   => 0,
    dirs        => [ ], 
};

umask 022;
my $help = 0;
$|++;
##test
debug("GetOptions");
GetOptions
( 
   "utf"           => \$Conf->{'utf'},
   "makesrt|srt"   => \$Conf->{'makesrt'},
   "removetxt"     => \$Conf->{'removetxt'},
   "force"         => \$Conf->{'force'},
   "debug|d"       => \$Conf->{'debug'},
   "test"          => \$Conf->{'test'},
   "save"          => \$Conf->{'saveconfig'},
   "once"          => \$Conf->{'once'},
   "cover"          => \$Conf->{'cover'},
   "dirs|dir=s"    => \@{ $Conf->{'dirs'} },
);

my $ConfTmp = get_options();

if (($ConfTmp)&&($Conf->{'once'}==0)){
  $Conf = $ConfTmp; 
}   

if($Conf->{'saveconfig'}){
   save_options();   
};

my @files;
my @dirs = @{$Conf->{dirs}};

debug("find");
find(\&wanted, @dirs);

foreach my $f (@files){
   if(($f =~ /(.*)\.$filter$/)&&!($f =~ /pl|PL|DUB|dub/)){
      if((!((-e "$1.srt")||(-e "$1.txt")))||($Conf->{'force'})){
         debug("Subs4 $f");
         print "\nSubs4 $f ";
         getsubtitles($f);
   };
  };
};

exit;

#========SUBS

sub hashfunction{

   my @in = @_;
   my @idx = ( 0xe, 0x3,  0x6, 0x8, 0x2 );
   my @mul = (   2,   2,    5,   4,   3 );
   my @add = (   0, 0xd, 0x10, 0xb, 0x5 );

   my $con;
   my $size = scalar @idx;

   my @init = split (//,$in[0]);


   for(my $i = 0; $i < $size; $i++){
      my $a = $add[$i];
      my $m = $mul[$i];
      my $i = $idx[$i];

      my $tmp = sprintf("%d",hex($init[$i]));
      my $t = $a + $tmp;
      
      
      my $t2 = '';
      $t2 = $init[$t+1] if defined $init[$t+1];
      my $strange = $init[$t].$t2;
      my $v = sprintf("%d",hex($strange));
      my $wrt = $v * $m;
      my $hwrt = sprintf("%x", $wrt);
      $hwrt =~ /.*(\w)$/;
      $con .= $1;
   }

   return $con;
}


sub getsubtitles{

   my $filename = shift;
   my $buf;
   my $data = 10485760;

   $filename =~ /(.+)\.(\w\w\w)$/;
   my $name = $1;
   my $ext = $2;
   my $nazwa = "$name.txt";

   open(my $FILE, '<', $filename) or die "ERR: Broken media file?";
   binmode $FILE;
   read $FILE, $buf, $data;
   close($FILE);

   my $md5 = md5_hex $buf;

   my @hash = hashfunction($md5);
   
   my $url = "http://napiprojekt.pl/unit_napisy/dl.php?l=PL&f=$md5&t=@hash&v=other&kolejka=false&nick=&pass=&napios=posix";
   my $filek = get($url);

   defined($filek) or die "ERR: Connection problem!";

   if ($filek ne 'NPc0'){
      my $filenameout = "napy.7z";

      open(my $MYFILE, '>', $filenameout) or die "ERR: Cant write napy.7z file!";
      binmode $MYFILE;
      print $MYFILE $filek;
      close($MYFILE);

    if ($Conf->{cover}){
        my $url_cover = "http://www.napiprojekt.pl/okladka_pobierz.php?id=$md5&oceny=-1";
        my $cover = get($url_cover);
        my $cover_name = "$name.jpg";
        open($MYFILE, '>', $cover_name) or die "ERR: Cant write cover file!";
            binmode $MYFILE;
        print $MYFILE $cover;
            close($MYFILE);
    }
    
      qx(/usr/bin/7za x -y -so -piBlm8NTigvru0Jr0 napy.7z 2>/dev/null > "$nazwa" );
      debug("unlink napy.7z");
      unlink "napy.7z";

      my $check_utf = qx(/usr/bin/file "$nazwa");

      debug("check utf: $check_utf");
 

         debug("open $nazwa");
         open(FD,"<",$nazwa) or die $!;
   my @lines = <FD>;
   close FD;
 
   debug("read file");
   my $file = join("",@lines);

      if ($Conf->{utf} && $check_utf !~ /UTF/) {

   my $from = "cp1250";
   my $to = "UTF-8";
   
   debug("from_to(file,$from,$to)");
   from_to($file,$from,$to);
      }

   debug("save $nazwa");
   open(FD,">",$nazwa);
   print FD $file;
   close(FD);

      if($Conf->{makesrt}){
         my $movierate = "25.00";

      my $fps = qx(/usr/bin/ffmpeg -i "$filename" 2>&1 | tr -s "\n" | grep Video | cut -d"," -f5 | cut -d" " -f2);
#     my $fps = qx(/usr/bin/exiftool "$filename" -s | /bin/grep VideoFrameRate | /usr/bin/cut -d":" -f2 | tr -d " ");
      chomp($fps);
      if($fps =~ /(\d\d\.*\d*)/){
#     if(($fps =~ /(\d\d\.\d\d\d)/)||($fps =~ /(\d\d\.\d\d)/)||($fps =~ /(\d\d)/)){
               $movierate = $1;
    print "--INFO:-f:$fps-s:$movierate";
            }

         my $response = '';
         debug("sub2srt -f=$movierate --force \"$nazwa\" \"$name.srt\"");
         $response = qx(/usr/bin/sub2srt -f=$movierate --force "$nazwa" "$name.srt") if!$Conf->{test};
         
         unless ($response =~ /Could not detect .*$/){
            if($Conf->{removetxt}){
               debug("unlink $nazwa");
               unlink $nazwa if!$Conf->{test};

    $name =~ m|^(.*[/\\])([^/\\]+?)$|;
#   sendEmail("relu\@simplusnet.pl", "localhost.mailing\@gmail.com", "$2", "subtitles for $2 downloaded" );
    print "--INFO: email sended";
#               print "--INFO: removed: '$nazwa'\n";
            }
#            print "--INFO: written: \"$name.srt\"\n";
         }else{
#            print "--INFO: written: \"$nazwa\"\n";
         }
      } # END MAKESRT
   } # END
   else{
      print "--INFO: No subs!";
   }

   return 0;
};

sub wanted {
   my $curr_file_name = $File::Find::name;
   if($curr_file_name =~ /.$filter$/){
      debug( $curr_file_name);
      push @files, $curr_file_name;
   };
};

sub debug {
   my $txt = shift || return;
   return if !$Conf->{debug};
   print $txt."    test mode:".$Conf->{test}."\n";
   return;
};

#############################################################################
### save options into file (using Data::Dumper)
sub save_options {
   $Conf->{saveconfig} = 0;
   my $d = Data::Dumper->new([$Conf]);
   $d->Purity(1)->Terse(1)->Deepcopy(1);
   open(FD,">/usr/bin/.getnapi.conf") or die "INFO: Can't open config file\n";
   print FD $d->Dump;
   print FD "1;\n";
   close FD;
}

#############################################################################
### load options from file
sub get_options {
   debug("open /usr/bin/.getnapi.conf");
   open(FD,"</usr/bin/.getnapi.conf") or return undef;
   my @conf = <FD>;
   close(FD);
   my $retconf = join('',@conf);
   if($retconf =~ /1;\n/sg){
      $retconf =~ s/1;\n//sg;
      return eval($retconf);
   };
   return undef;
}

sub sendEmail{
  my ($to, $from, $subject, $message) = @_;
  my $sendmail = '/usr/lib/sendmail';
  open(MAIL, "|$sendmail -oi -t");
    print MAIL "From: $from\n";
    print MAIL "To: $to\n";
    print MAIL "Subject: $subject\n\n";
    print MAIL "$message\n";
  close(MAIL);
}

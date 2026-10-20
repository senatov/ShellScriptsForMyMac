#!/bin/zsh
# Show top processes or summarize the first level of a directory on macOS.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: top10.zsh MODE [N] [PATH]

Processes (PATH is not used):
  cpu [N]           Top processes by CPU usage
  mem [N]           Top processes by memory usage
  both [N]          Show both process lists
  live [N]          Refresh both lists every 2 seconds (Ctrl-C to stop)

Files and directories (PATH defaults to the current directory):
  size [N] [PATH]   First-level files and directories by disk space used
  files [N] [PATH]  First-level directories by number of contained files
  dirs [N] [PATH]   First-level directories by number of contained directories

N defaults to 10 and must be a positive integer. Files and directories are
counted recursively inside each first-level directory; the directory itself
is not included in its directory count. Hidden entries are included. Symbolic
links are measured but are not followed. PATH can also be given directly after
the file mode when the default N is desired.

Examples:
  top10.zsh cpu 15
  top10.zsh size ~/Downloads
  top10.zsh size 20 ~/Downloads
  top10.zsh files 10 .
  top10.zsh dirs 10 /Users
EOF
}

if (( $# == 0 )); then
  usage
  exit 0
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

MODE="$1"
N="${2:-10}"
PATH_TO_SCAN="${3:-.}"

if [[ "$MODE" == (size|files|dirs) && $# == 2 && ! "$2" =~ '^[0-9]+$' ]]; then
  N=10
  PATH_TO_SCAN="$2"
fi

if [[ ! "$N" =~ '^[0-9]+$' ]] || (( N < 1 )); then
  print -u2 'N must be a positive integer.'
  exit 2
fi

print_top() {
  local title="$1" sortkey="$2" count="$3"
  print "\n>>> ${title} (top ${count})"
  print ' PID   PPID USER            %CPU  %MEM COMMAND'
  LC_ALL=C ps -axo 'pid,ppid,user,%cpu,%mem,comm' \
    | awk 'NR > 1' \
    | LC_ALL=C sort -k"${sortkey}","${sortkey}"nr \
    | awk -v limit="$count" 'NR <= limit'
}

case "$MODE" in
  cpu|mem|both|live)
    if (( $# > 2 )); then
      print -u2 "${MODE} accepts only N; PATH is for file modes."
      exit 2
    fi
    case "$MODE" in
      cpu)  print_top 'By CPU' 4 "$N" ;;
      mem)  print_top 'By Memory' 5 "$N" ;;
      both) print_top 'By CPU' 4 "$N"; print_top 'By Memory' 5 "$N" ;;
      live)
        while true; do
          clear
          date +'%F %T'
          print_top 'By CPU' 4 "$N"
          print_top 'By Memory' 5 "$N"
          sleep 2
        done
        ;;
    esac
    ;;
  size|files|dirs)
    if (( $# > 3 )); then
      print -u2 "Too many arguments for ${MODE}."
      exit 2
    fi
    if [[ ! -d "$PATH_TO_SCAN" ]]; then
      print -u2 "Not a directory: ${PATH_TO_SCAN}"
      exit 2
    fi
    perl - "$MODE" "$N" "$PATH_TO_SCAN" <<'PERL'
use strict;
use warnings;
use File::Find;

my ($mode, $limit, $root) = @ARGV;
opendir(my $directory, $root) or die "Cannot read $root: $!\n";
my @names = grep { $_ ne '.' && $_ ne '..' } readdir($directory);
closedir($directory);

my @rows;
for my $name (@names) {
    my $path = "$root/$name";
    my @entry = lstat($path);
    next unless @entry;
    my $is_dir = -d _;
    next if $mode ne 'size' && !$is_dir;

    my ($blocks, $files, $dirs) = (0, 0, 0);
    if ($is_dir) {
        my %seen;
        find({
            no_chdir => 1,
            wanted => sub {
                my @stat = lstat($_);
                return unless @stat;
                my $key = "$stat[0]:$stat[1]";
                $blocks += $stat[12] unless $seen{$key}++;
                return if $_ eq $path;
                if (-d _) { ++$dirs }
                elsif (-f _) { ++$files }
            }
        }, $path);
    } else {
        $blocks = $entry[12];
        $files = 1 if -f _;
    }
    push @rows, { name => $name, type => ($is_dir ? 'dir' : (-l $path ? 'link' : 'file')),
                  bytes => $blocks * 512, files => $files, dirs => $dirs };
}

my $key = $mode eq 'size' ? 'bytes' : $mode;
@rows = sort { $b->{$key} <=> $a->{$key} || $a->{name} cmp $b->{name} } @rows;

sub readable_size {
    my ($bytes) = @_;
    my @units = ('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB');
    my $index = 0;
    while ($bytes >= 1024 && $index < $#units) {
        $bytes /= 1024;
        ++$index;
    }
    return $index ? sprintf('%.1f %s', $bytes, $units[$index]) : "$bytes B";
}

printf "First-level entries in %s, ranked by %s (top %d)\n", $root, $mode, $limit;
printf "%-5s %12s %10s %10s  %s\n", 'TYPE', 'SIZE', 'FILES', 'DIRS', 'NAME';
for my $row (@rows[0 .. ($#rows < $limit - 1 ? $#rows : $limit - 1)]) {
    my $name = $row->{name};
    $name =~ s/([\n\r\t])/sprintf('\\x{%02X}', ord($1))/ge;
    printf "%-5s %12s %10d %10d  %s\n", $row->{type}, readable_size($row->{bytes}),
        $row->{files}, $row->{dirs}, $name;
}
PERL
    ;;
  *)
    print -u2 "Unknown mode: ${MODE}"
    usage >&2
    exit 2
    ;;
esac

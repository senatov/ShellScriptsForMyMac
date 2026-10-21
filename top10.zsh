#!/bin/zsh
# Show top processes or rank directories on macOS.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: top10.zsh MODE [N] [PATH]

Processes (PATH is not used):
  cpu [N]           Top processes by CPU usage
  mem [N]           Top processes by memory usage
  both [N]          Show both process lists
  live [N]          Refresh both lists every 2 seconds (Ctrl-C to stop)

Filesystem:
  entries [N] [PATH]  Top directories by total immediate children (default: /)
  files [N] [PATH]    Top directories by immediate files (default: /)
  dirs [N] [PATH]     Top directories by immediate directories (default: /)
  size [N] [PATH]     Immediate children of PATH by recursive disk use (default: .)

N defaults to 10 and must be a positive integer. entries/files/dirs search the
whole tree beneath PATH, excluding PATH itself, but count only each directory's
immediate children. FILES includes links and other non-directory entries.
Hidden entries count; symbolic links are not followed. Mounted volumes and
macOS's duplicate /System/Volumes/Data view are not traversed when scanning /.
Unreadable directories have unknown child counts and are excluded from the
ranking; the report states how many were skipped. PATH can follow MODE directly.
size keeps its existing recursive disk-usage meaning and marks partial results.

Examples:
  top10.zsh cpu 15
  top10.zsh entries                 # OS-wide top 10, no sudo required
  top10.zsh dirs 10 /Users/senat    # search only this subtree
  top10.zsh files 20 /
  top10.zsh size 20 ~/Downloads
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
PATH_TO_SCAN="${3:-/}"
[[ "$MODE" == size && $# < 3 ]] && PATH_TO_SCAN=.

if [[ "$MODE" == (size|files|dirs|entries) && $# == 2 && ! "$2" =~ '^[0-9]+$' ]]; then
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
  size|files|dirs|entries)
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
use Cwd qw(abs_path);

my ($mode, $limit, $root) = @ARGV;
$root = abs_path($root) // die "Cannot resolve $root: $!\n";

sub display_path {
    my ($path) = @_;
    $path =~ s/([\n\r\t])/sprintf('\\x{%02X}', ord($1))/ge;
    return $path;
}

if ($mode ne 'size') {
    my @root_stat = stat($root);
    my $root_device = $root_stat[0];
    my @stack = ($root);
    my %seen;
    my @rows;
    my $readable = 0;
    my ($unreadable, $mounts, $duplicates, $stat_failures) = (0, 0, 0, 0);

    while (@stack) {
        my $path = pop @stack;
        my @self = lstat($path);
        if (!@self) { ++$stat_failures; next }
        my $identity = "$self[0]:$self[1]";
        if ($seen{$identity}++) { ++$duplicates; next }
        if ($path ne $root && $self[0] != $root_device) { ++$mounts; next }
        # Data is the second view of macOS's writable root volume. Its entries
        # are reached through /Users, /Library, /private, and other root paths.
        if ($root eq '/' && $path eq '/System/Volumes/Data') {
            ++$duplicates;
            next;
        }

        my $directory;
        if (!opendir($directory, $path)) { ++$unreadable; next }
        ++$readable;
        my ($files, $dirs) = (0, 0);
        while (defined(my $name = readdir($directory))) {
            next if $name eq '.' || $name eq '..';
            my $child = $path eq '/' ? "/$name" : "$path/$name";
            my @entry = lstat($child);
            if (!@entry) { ++$stat_failures; next }
            if (-d _) {
                ++$dirs;
                push @stack, $child;
            } else {
                ++$files;
            }
        }
        closedir($directory);
        next if $path eq $root;
        my $row = { path => $path, files => $files, dirs => $dirs,
                    entries => $files + $dirs };
        if (@rows < $limit || $row->{$mode} > $rows[-1]->{$mode} ||
            ($row->{$mode} == $rows[-1]->{$mode} && $path lt $rows[-1]->{path})) {
            @rows = sort { $b->{$mode} <=> $a->{$mode} || $a->{path} cmp $b->{path} }
                (@rows, $row);
            pop @rows if @rows > $limit;
        }
    }

    printf "Directories beneath %s, ranked by immediate %s (top %d)\n",
        display_path($root), $mode, $limit;
    printf "%-8s %8s %8s  %s\n", 'TOTAL', 'DIRS', 'FILES*', 'DIRECTORY';
    for my $row (@rows) {
        printf "%8d %8d %8d  %s\n", $row->{entries}, $row->{dirs},
            $row->{files}, display_path($row->{path});
    }
    print "* FILES includes symbolic links and other non-directory entries.\n";
    printf "Scanned %d readable directories; %d unreadable, %d other mounts, %d duplicate views, %d vanished/unstatable entries skipped.\n",
        $readable, $unreadable, $mounts, $duplicates, $stat_failures;
    print "Ranking is limited to readable directories; unreadable child counts are unknown.\n"
        if $unreadable || $stat_failures;
    exit 0;
}

opendir(my $directory, $root) or die "Cannot read $root: $!\n";
my @names = grep { $_ ne '.' && $_ ne '..' } readdir($directory);
closedir($directory);

my @rows;
my $skipped_total = 0;
for my $name (@names) {
    my $path = $root eq '/' ? "/$name" : "$root/$name";
    my @entry = lstat($path);
    next unless @entry;
    my $is_dir = -d _;
    next if $mode ne 'size' && !$is_dir;

    my ($blocks, $files, $dirs) = (0, 0, 0);
    my $skipped = 0;
    if ($is_dir) {
        my %seen;
        local $SIG{__WARN__} = sub {
            my ($warning) = @_;
            if ($warning =~ /^Can't opendir\(/) {
                ++$skipped;
            } else {
                warn $warning;
            }
        };
        find({
            no_chdir => 1,
            wanted => sub {
                my @stat = lstat($_);
                if (!@stat) {
                    ++$skipped;
                    return;
                }
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
    $skipped_total += $skipped;
    push @rows, { name => $name, type => ($is_dir ? 'dir' : (-l $path ? 'link' : 'file')),
                  bytes => $blocks * 512, files => $files, dirs => $dirs,
                  partial => $skipped ? 'partial' : '' };
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

printf "Immediate children of %s, ranked by recursive disk use (top %d)\n",
    display_path($root), $limit;
printf "%-5s %12s %10s %10s %-7s  %s\n", 'TYPE', 'SIZE', 'FILES', 'DIRS', 'STATUS', 'PATH';
for my $row (@rows[0 .. ($#rows < $limit - 1 ? $#rows : $limit - 1)]) {
    my $path = $root eq '/' ? "/$row->{name}" : "$root/$row->{name}";
    printf "%-5s %12s %10d %10d %-7s  %s\n", $row->{type}, readable_size($row->{bytes}),
        $row->{files}, $row->{dirs}, $row->{partial}, display_path($path);
}
print "SIZE is allocated disk space; FILES and DIRS count nested entries recursively.\n";
if ($skipped_total) {
    printf "\nPartial results: %d directories or entries could not be read. ", $skipped_total;
    print "Sizes and counts may be underestimated; the ranking may change with access.";
}
PERL
    ;;
  *)
    print -u2 "Unknown mode: ${MODE}"
    usage >&2
    exit 2
    ;;
esac

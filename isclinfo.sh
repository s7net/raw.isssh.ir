#!/usr/bin/env bash

INCLUDE_SYSTEM_PHP=true

php_bins=()

if [[ -d /usr/local/directadmin ]]; then
  for bin in /usr/local/php*/bin/php; do
    [[ -x "$bin" ]] && php_bins+=("$bin")
  done
elif [[ -d /opt/cpanel ]]; then
  for bin in /opt/cpanel/ea-php*/root/usr/bin/php; do
    [[ -x "$bin" ]] && php_bins+=("$bin")
  done
fi

if [[ "$INCLUDE_SYSTEM_PHP" == true && -x "$(command -v php)" ]]; then
  php_bins+=("$(command -v php)")
fi

if ((${#php_bins[@]} == 0)); then
  echo "No PHP binaries found."
  exit 1
fi

php_bins=($(printf "%s\n" "${php_bins[@]}" | awk '!seen[$0]++'))

echo "Detected PHP binaries:"
echo "----------------------"
i=1
for bin in "${php_bins[@]}"; do
  ver="$("$bin" -v 2>/dev/null | head -n1)"
  [[ -z "$ver" ]] && ver="(version unknown)"
  printf " [%d] %s\n     %s\n\n" "$i" "$ver" "$bin"
  ((i++))
done

read -rp "Select the PHP version number to use: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#php_bins[@]} )); then
  echo "Invalid choice."
  exit 1
fi

selected_php="${php_bins[$((choice-1))]}"

clear
echo "Using PHP binary: $selected_php"
echo

while true; do
  echo "================ PHP Environment Inspector ================"
  echo "Using: $selected_php"
  echo
  echo "Select a section to view:"
  echo "  1) General Info"
  echo "  2) SourceGuardian / ionCube"
  echo "  3) Active Extensions"
  echo "  4) Inactive Known Extensions"
  echo "  5) Disabled Dangerous Functions"
  echo "  6) Raw disable_functions"
  echo "  7) Show ALL sections"
  echo "  0) Quit"
  echo "--------------------------------------------------------"
  read -rp "Enter choice: " sec

  case "$sec" in
    0|q|Q)
      clear
      echo "Bye."
      exit 0
      ;;
    1) SECTION="general" ;;
    2) SECTION="sg" ;;
    3) SECTION="active" ;;
    4) SECTION="inactive" ;;
    5) SECTION="danger" ;;
    6) SECTION="raw" ;;
    7) SECTION="all" ;;
    *)
      clear
      echo "Invalid choice."
      echo
      continue
      ;;
  esac

  clear
  echo "=== Section: $SECTION ==="
  echo

  SECTION="$SECTION" "$selected_php" <<'PHP'
<?php

function color($t,$c){return "\033[".$c."m".$t."\033[0m";}

$section=getenv('SECTION')?:'general';

$active=get_loaded_extensions();sort($active);
$all=["bcmath","bz2","calendar","Core","ctype","curl","date","dba","dom","exif","FFI","fileinfo","filter","ftp","gd","gettext","gmp","hash","iconv","imap","intl","json","ldap","libxml","mbstring","mysqli","mysqlnd","odbc","openssl","pcntl","pcre","PDO","pdo_mysql","pdo_pgsql","pdo_sqlite","pdo_odbc","Phar","posix","readline","Reflection","session","shmop","SimpleXML","snmp","soap","sockets","sodium","sqlite3","standard","sysvmsg","sysvsem","sysvshm","tokenizer","xml","xmlreader","xmlwriter","xsl","Zend OPcache","zip","zlib","imagick","ionCube Loader","apcu","redis","memcached"];
sort($all);
$inactive=array_diff($all,$active);

$pv=phpversion();
$srv=$_SERVER['SERVER_SOFTWARE']??'Unknown';
$os=php_uname();
$mem=ini_get('memory_limit');
$upl=ini_get('upload_max_filesize');
$post=ini_get('post_max_size');
$met=ini_get('max_execution_time');
$miv=ini_get('max_input_vars');
$dis=ini_get('display_errors')?'On':'Off';
$auf=ini_get('allow_url_fopen')?'On':'Off';
$ini=php_ini_loaded_file()?:'Unknown';
$zend=zend_version();

$df=["shell_exec","system","passthru","exec","popen","ini_restore","socket_create","socket_create_listen","socket_create_pair","socket_listen","socket_bind","symlink","link","pfsockopen","ini_alter","dl","pcntl_exec","pcntl_fork","proc_close","proc_open","proc_terminate","posix_kill","posix_mkfifo","posix_setpgid","posix_setsid","posix_setuid","posix_setgid","posix_uname","show_source","getfile","mkfifo"];
$disabled=ini_get('disable_functions');
$disabled=$disabled?array_map('trim',explode(',',$disabled)):[];
$real=array_intersect($df,$disabled);

$sg=extension_loaded('SourceGuardian');
$ic=extension_loaded('ionCube Loader');
$sgs=$sg?'Enabled':'Disabled';
$ics=$ic?'Enabled':'Disabled';
$sgv=$sg?phpversion('SourceGuardian'):'-';
$icv=($ic&&function_exists('ioncube_loader_version'))?ioncube_loader_version():'-';

function general($pv,$zend,$srv,$os,$ini,$mem,$upl,$post,$met,$miv,$dis,$auf){
  echo color("General Info","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "PHP Version        : $pv\nZend Engine        : $zend\nServer Software    : $srv\nOperating System   : $os\nLoaded php.ini     : $ini\nmemory_limit       : $mem\nupload_max_filesize: $upl\npost_max_size      : $post\nmax_execution_time : $met seconds\nmax_input_vars     : ".($miv?:'not set')."\ndisplay_errors     : $dis\nallow_url_fopen    : $auf\n";
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function sgic($sgs,$sgv,$ics,$icv){
  echo color("SourceGuardian / ionCube","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "SourceGuardian:\n  Status : $sgs\n  Version: $sgv\n\nionCube Loader:\n  Status : $ics\n  Version: $icv\n";
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function active($a){
  echo color("Active Extensions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "Active extensions (".count($a)."):\n";
  echo $a?implode(", ",$a):"(none)";
  echo PHP_EOL.str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function inactive($a){
  echo color("Inactive Known Extensions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "Inactive known extensions (".count($a)."):\n";
  echo $a?implode(", ",$a):"(none or not detectable)";
  echo PHP_EOL.str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function danger($r){
  echo color("Disabled Dangerous Functions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  if($r){echo "These high-risk functions are disabled:\n".implode(", ",$r).PHP_EOL;}
  else{echo "No dangerous functions disabled.\n";}
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function rawdf($d){
  echo color("Raw disable_functions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo $d?"disable_functions list:\n".implode(", ",$d):"(disable_functions is empty)";
  echo PHP_EOL.str_repeat("-",60).PHP_EOL.PHP_EOL;
}

switch($section){
  case 'general': general($pv,$zend,$srv,$os,$ini,$mem,$upl,$post,$met,$miv,$dis,$auf); break;
  case 'sg': sgic($sgs,$sgv,$ics,$icv); break;
  case 'active': active($active); break;
  case 'inactive': inactive($inactive); break;
  case 'danger': danger($real); break;
  case 'raw': rawdf($disabled); break;
  case 'all':
  default:
    general($pv,$zend,$srv,$os,$ini,$mem,$upl,$post,$met,$miv,$dis,$auf);
    sgic($sgs,$sgv,$ics,$icv);
    active($active);
    inactive($inactive);
    danger($real);
    rawdf($disabled);
    break;
}
PHP

  echo
  read -rp "Press Enter to go back to menu..." _
  clear
done

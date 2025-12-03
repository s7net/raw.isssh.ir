<?php
$activeModules = get_loaded_extensions();
sort($activeModules);

$allKnownModules = [
    "bcmath","bz2","calendar","Core","ctype","curl","date","dba","dom","exif","FFI",
    "fileinfo","filter","ftp","gd","gettext","gmp","hash","iconv","imap","intl","json",
    "ldap","libxml","mbstring","mysqli","mysqlnd","odbc","openssl","pcntl","pcre","PDO",
    "pdo_mysql","pdo_pgsql","pdo_sqlite","pdo_odbc","Phar","posix","readline","Reflection",
    "session","shmop","SimpleXML","snmp","soap","sockets","sodium","sqlite3","standard",
    "sysvmsg","sysvsem","sysvshm","tokenizer","xml","xmlreader","xmlwriter","xsl",
    "Zend OPcache","zip","zlib","imagick","ionCube Loader","apcu","redis","memcached"
];
sort($allKnownModules);

$inactiveModules = array_diff($allKnownModules, $activeModules);

$phpVersion   = phpversion();
$server       = $_SERVER['SERVER_SOFTWARE'] ?? 'نامشخص';
$os           = php_uname();
$memoryLimit  = ini_get('memory_limit');
$uploadMax    = ini_get('upload_max_filesize');
$postMax      = ini_get('post_max_size');
$maxExecTime  = ini_get('max_execution_time');
$maxInputVars = ini_get('max_input_vars');
$displayErr   = ini_get('display_errors') ? 'فعال' : 'غیرفعال';
$allowUrlFopen= ini_get('allow_url_fopen') ? 'فعال' : 'غیرفعال';
$phpIniPath   = php_ini_loaded_file() ?: 'نامشخص';
$zendVersion  = zend_version();

$dangerousFuncs = [
    "shell_exec","system","passthru","exec","popen","ini_restore","socket_create",
    "socket_create_listen","socket_create_pair","socket_listen","socket_bind","symlink",
    "link","pfsockopen","ini_alter","dl","pcntl_exec","pcntl_fork","proc_close",
    "proc_open","proc_terminate","posix_kill","posix_mkfifo","posix_setpgid",
    "posix_setsid","posix_setuid","posix_setgid","posix_uname","show_source",
    "getfile","mkfifo"
];

$disabledFuncs = explode(',', ini_get('disable_functions'));
$disabledFuncs = array_map('trim', $disabledFuncs);
$reallyDisabled = array_intersect($dangerousFuncs, $disabledFuncs);

$sourceGuardianStatus = extension_loaded('SourceGuardian') ? 'فعال' : 'غیرفعال';
$ioncubeStatus = extension_loaded('ionCube Loader') ? 'فعال' : 'غیرفعال';
$redisStatus = extension_loaded('redis') ? 'فعال' : 'غیرفعال';

$sourceGuardianVersion = $sourceGuardianStatus === 'فعال' ? phpversion('SourceGuardian') : '-';
$ioncubeVersion = $ioncubeStatus === 'فعال' ? ioncube_loader_version() : '-';
$redisVersion = $redisStatus === 'فعال' ? phpversion('redis') : '-';
?>
<!DOCTYPE html>
<html lang="fa">
<head>
  <meta charset="UTF-8">
  <title>اطلاعات نسخه PHP | ایران سرور</title>
  <meta name="robots" content="noindex, nofollow">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/rastikerdar/vazir-font@v30.1.0/dist/font-face.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
  <style>
    body{font-family:'Vazir',Tahoma,sans-serif;background:#f4f7fe;direction:rtl;margin:0}
    header{background:linear-gradient(90deg,#1e3cfc,#4c6ef5);color:#fff;text-align:center;padding:20px;font-size:20px;font-weight:bold}
    header span{display:block;font-size:14px;opacity:.9}
    .container{max-width:1100px;margin:30px auto;padding:25px;background:#fff;border-radius:20px;box-shadow:0 6px 20px rgba(0,0,0,.08)}
    h2{color:#1e3cfc;border-bottom:2px solid #e9ecef;padding-bottom:8px;margin:20px 0;font-size:18px}
    table{width:100%;border-collapse:collapse;margin-bottom:25px}
    table td{padding:10px 12px;border-bottom:1px solid #e9ecef;font-size:15px}
    table td i{color:#4c6ef5;margin-left:6px}
    table tr:last-child td{border-bottom:none}
    .search-box{position:relative;margin:20px 0}
    .search-box input{width:100%;padding:12px 40px;border:1px solid #cfe0ff;border-radius:12px;font-family:'Vazir';box-sizing:border-box}
    .search-box i{position:absolute;right:12px;top:50%;transform:translateY(-50%);color:#4c6ef5}
    ul{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px}
    li{padding:12px;border-radius:10px;font-size:14px;display:flex;align-items:center;gap:8px;border:1px solid #dee2e6}
    .active-module{background:#e6ffed;border-color:#b2f2bb;color:#2b8a3e}
    .inactive-module{background:#ffe3e3;border-color:#ffa8a8;color:#c92a2a}
    .disabled-func{background:#f3e8ff;border-color:#d0bfff;color:#7048e8}
    .status-card-container{display:flex;gap:20px;flex-wrap:wrap;margin:20px 0}
    .status-card{
        flex:1 1 250px;
        background:linear-gradient(145deg,#f8f9fa,#e9ecef);
        border-radius:15px;
        padding:20px;
        box-shadow:0 4px 10px rgba(0,0,0,.05);
        text-align:center;
        transition:all .3s ease;
    }
    .status-card:hover{transform:translateY(-4px);box-shadow:0 6px 14px rgba(0,0,0,.1)}
    .status-icon{font-size:36px;margin-bottom:10px}
    .status-active{color:#2b8a3e}
    .status-inactive{color:#c92a2a}
    .status-name{font-size:16px;font-weight:bold;color:#333}
    .status-version{font-size:14px;color:#666;margin-top:4px}
    .no-result{text-align:center;color:#999;margin-top:15px;display:none}
  </style>
</head>
<body>
<header>
  ایران سرور
  <span>اطلاعات نسخه PHP</span>
</header>
<div class="container">
  <h2>اطلاعات کلی</h2>
  <table>
    <tr><td><i class="fa fa-code"></i>نسخه PHP:</td><td><?= $phpVersion ?></td></tr>
    <tr><td><i class="fa fa-server"></i>وب‌سرور:</td><td><?= $server ?></td></tr>
    <tr><td><i class="fa fa-desktop"></i>سیستم عامل:</td><td><?= $os ?></td></tr>
    <tr><td><i class="fa fa-memory"></i>محدودیت حافظه:</td><td><?= $memoryLimit ?></td></tr>
    <tr><td><i class="fa fa-upload"></i>حداکثر حجم آپلود:</td><td><?= $uploadMax ?></td></tr>
    <tr><td><i class="fa fa-database"></i>حداکثر حجم POST:</td><td><?= $postMax ?></td></tr>
    <tr><td><i class="fa fa-clock"></i>حداکثر زمان اجرا:</td><td><?= $maxExecTime ?> ثانیه</td></tr>
    <tr><td><i class="fa fa-list"></i>حداکثر ورودی‌ها:</td><td><?= $maxInputVars ?></td></tr>
    <tr><td><i class="fa fa-bug"></i>نمایش خطاها:</td><td><?= $displayErr ?></td></tr>
    <tr><td><i class="fa fa-link"></i>allow_url_fopen:</td><td><?= $allowUrlFopen ?></td></tr>
    <tr><td><i class="fa fa-cog"></i>مسیر php.ini:</td><td><?= $phpIniPath ?></td></tr>
    <tr><td><i class="fa fa-bolt"></i>Zend Engine:</td><td><?= $zendVersion ?></td></tr>
  </table>

  <h2>وضعیت سورس گاردین، ionCube و Redis</h2>
  <div class="status-card-container">

    <div class="status-card">
      <div class="status-icon <?= $sourceGuardianStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <i class="fa fa-shield-halved"></i>
      </div>
      <div class="status-name">SourceGuardian</div>
      <div class="<?= $sourceGuardianStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <?= $sourceGuardianStatus ?>
      </div>
      <?php if ($sourceGuardianVersion !== '-'): ?>
      <div class="status-version">نسخه: <?= $sourceGuardianVersion ?></div>
      <?php endif; ?>
    </div>

    <div class="status-card">
      <div class="status-icon <?= $ioncubeStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <i class="fa fa-lock"></i>
      </div>
      <div class="status-name">ionCube Loader</div>
      <div class="<?= $ioncubeStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <?= $ioncubeStatus ?>
      </div>
      <?php if ($ioncubeVersion !== '-'): ?>
      <div class="status-version">نسخه: <?= $ioncubeVersion ?></div>
      <?php endif; ?>
    </div>

    <div class="status-card">
      <div class="status-icon <?= $redisStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <i class="fa fa-database"></i>
      </div>
      <div class="status-name">Redis (PHP Extension)</div>
      <div class="<?= $redisStatus === 'فعال' ? 'status-active' : 'status-inactive' ?>">
        <?= $redisStatus ?>
      </div>
      <?php if ($redisVersion !== '-'): ?>
      <div class="status-version">نسخه: <?= $redisVersion ?></div>
      <?php endif; ?>
    </div>

  </div>

  <h2>جستجو در ماژول‌ها</h2>
  <div class="search-box">
    <i class="fa fa-search"></i>
    <input type="text" id="searchBox" placeholder="جستجوی ماژول...">
  </div>

  <h2>ماژول‌های فعال</h2>
  <ul id="activeList">
    <?php foreach ($activeModules as $m): ?>
      <li class="active-module"><i class="fa fa-check"></i><?= htmlspecialchars($m) ?></li>
    <?php endforeach; ?>
  </ul>

  <h2>ماژول‌های غیرفعال</h2>
  <ul id="inactiveList">
    <?php foreach ($inactiveModules as $m): ?>
      <li class="inactive-module"><i class="fa fa-xmark"></i><?= htmlspecialchars($m) ?></li>
    <?php endforeach; ?>
  </ul>

  <h2>توابع غیرفعال</h2>
  <ul>
    <?php if (!empty($reallyDisabled)): ?>
      <?php foreach ($reallyDisabled as $f): ?>
        <li class="disabled-func"><i class="fa fa-ban"></i><?= htmlspecialchars($f) ?></li>
      <?php endforeach; ?>
    <?php else: ?>
      <li class="disabled-func">هیچ تابعی غیرفعال نشده است</li>
    <?php endif; ?>
  </ul>

  <div class="no-result" id="noResult">ماژولی با این نام پیدا نشد.</div>
</div>

<script>
const searchBox = document.getElementById('searchBox');
const lists = [document.getElementById('activeList'), document.getElementById('inactiveList')];
const noResult = document.getElementById('noResult');

searchBox.addEventListener('keyup', function () {
  const filter = this.value.toLowerCase();
  let found = false;
  lists.forEach(list => {
    const items = list.getElementsByTagName('li');
    for (let i=0;i<items.length;i++) {
      const txt = items[i].textContent.toLowerCase();
      if (txt.includes(filter)) {
        items[i].style.display = '';
        found = true;
      } else {
        items[i].style.display = 'none';
      }
    }
  });
  noResult.style.display = found ? 'none' : 'block';
});
</script>
</body>
</html>

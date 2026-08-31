<?php
// ============================================================
// lookup_hsc.php - Proxy pencarian sparepart ke hargasukucadang.online
// Mengembalikan JSON: { results: [ {kode, nama, harga, status, tipe}, ... ] }
// Dipakai oleh form Tambah/Edit Sparepart untuk mengisi Kode & Nama otomatis.
// ============================================================
require_once __DIR__ . '/../includes/db.php';
require_once __DIR__ . '/../includes/auth.php';
require_login();
header('Content-Type: application/json; charset=utf-8');

$field = $_GET['field'] ?? 'nama';           // nama | kode | tipe
$q     = trim($_GET['q'] ?? '');

if ($q === '' || mb_strlen($q) < 2) {
    echo json_encode(['results' => [], 'error' => 'Kata kunci minimal 2 karakter.']);
    exit;
}

// Susun payload sesuai form situs sumber; field tak-terpakai diisi placeholder default
$payload = [
    'kodepart' => '--Kode Part--',
    'namapart' => '--Nama Part--',
    'tipe'     => '--Motor--',
    'submit'   => '',
];
if ($field === 'kode')      $payload['kodepart'] = $q;
elseif ($field === 'tipe')  $payload['tipe']     = $q;
else                        $payload['namapart'] = $q;

$html = hsc_fetch('https://hargasukucadang.online/index.php', $payload);
if ($html === null) {
    echo json_encode(['results' => [], 'error' => 'Gagal menghubungi hargasukucadang.online. Pastikan server terhubung internet, lalu coba lagi.']);
    exit;
}

echo json_encode(['results' => hsc_parse($html)]);

// ------------------------------------------------------------
// Ambil HTML hasil pencarian (POST). Utamakan cURL, fallback file_get_contents.
function hsc_fetch(string $url, array $post): ?string {
    $body = http_build_query($post);

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_USERAGENT      => 'Mozilla/5.0 (compatible; SimbengBengkel/1.0)',
            CURLOPT_HTTPHEADER     => ['Content-Type: application/x-www-form-urlencoded'],
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($res !== false && $code >= 200 && $code < 400) return $res;
        return null;
    }

    // Fallback bila cURL tidak tersedia
    $ctx = stream_context_create([
        'http' => [
            'method'  => 'POST',
            'header'  => "Content-Type: application/x-www-form-urlencoded\r\nUser-Agent: SimbengBengkel/1.0\r\n",
            'content' => $body,
            'timeout' => 20,
        ],
        'ssl' => ['verify_peer' => false, 'verify_peer_name' => false],
    ]);
    $res = @file_get_contents($url, false, $ctx);
    return $res === false ? null : $res;
}

// ------------------------------------------------------------
// Parse tabel hasil (id="customers") menjadi array asosiatif.
function hsc_parse(string $html): array {
    $out  = [];
    $prev = libxml_use_internal_errors(true);
    $doc  = new DOMDocument();
    $doc->loadHTML('<?xml encoding="UTF-8">' . $html);
    libxml_clear_errors();
    libxml_use_internal_errors($prev);

    $xp   = new DOMXPath($doc);
    $rows = $xp->query("//table[@id='customers']/tbody/tr");
    if ($rows === false) return $out;

    foreach ($rows as $tr) {
        $tds = $xp->query('./td', $tr);
        if ($tds->length < 5) continue;
        $get = function ($i) use ($tds) {
            return trim(preg_replace('/\s+/', ' ', $tds->item($i)->textContent));
        };
        $kode = $get(0);
        $nama = $get(1);
        if ($kode === '' && $nama === '') continue;
        $out[] = [
            'kode'   => $kode,
            'nama'   => $nama,
            'harga'  => $get(2),
            'status' => $get(3),
            'tipe'   => $get(4),
        ];
        if (count($out) >= 30) break;
    }
    return $out;
}

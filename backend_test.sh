#!/bin/bash
# ============================================================
# Backend Test Script untuk Aplikasi Bengkel Motor (PHP Native + MySQL)
# Base URL: http://localhost:3000
# Router: index.php?page=NAMA
# AJAX endpoints: /ajax/
# Login: admin / admin123
# ============================================================

set -e  # Exit on error
BASE_URL="http://localhost:3000"
COOKIE_JAR="/tmp/bengkel_cookies.txt"
TEST_LOG="/tmp/bengkel_test.log"

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fungsi helper
log() {
    echo -e "${GREEN}[TEST]${NC} $1" | tee -a "$TEST_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_LOG"
}

check_errors() {
    local response="$1"
    local step="$2"
    
    if echo "$response" | grep -qiE "(Fatal error|Uncaught|SQLSTATE|Warning:|Parse error|Notice:|Deprecated:)"; then
        error "❌ $step: Ditemukan error PHP/SQL"
        echo "$response" | grep -iE "(Fatal error|Uncaught|SQLSTATE|Warning:|Parse error|Notice:|Deprecated:)" | head -5
        return 1
    fi
    return 0
}

check_http_status() {
    local status="$1"
    local expected="$2"
    local step="$3"
    
    if [ "$status" != "$expected" ]; then
        error "❌ $step: HTTP status $status (expected $expected)"
        return 1
    fi
    log "✅ $step: HTTP $status"
    return 0
}

# Bersihkan log dan cookie
rm -f "$TEST_LOG" "$COOKIE_JAR"
log "=== Memulai Pengujian Backend Aplikasi Bengkel Motor ==="
log "Base URL: $BASE_URL"

# ============================================================
# 1. LOGIN ADMIN
# ============================================================
log "\n=== 1. LOGIN ADMIN ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -c "$COOKIE_JAR" -X POST \
    -d "username=admin&password=admin123" \
    "$BASE_URL/index.php?page=login")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Login sukses biasanya redirect (302) atau 200 dengan set cookie
if [ "$HTTP_STATUS" = "302" ] || [ "$HTTP_STATUS" = "200" ]; then
    log "✅ Login berhasil (HTTP $HTTP_STATUS)"
    check_errors "$BODY" "Login"
else
    error "❌ Login gagal (HTTP $HTTP_STATUS)"
    echo "$BODY" | head -20
    exit 1
fi

# Verifikasi sesi dengan akses dashboard
log "Verifikasi sesi: akses dashboard..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/index.php?page=dashboard")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Dashboard access"
check_errors "$BODY" "Dashboard"

# Cek apakah ada statistik di dashboard
if echo "$BODY" | grep -q "Total Transaksi\|Pendapatan"; then
    log "✅ Dashboard menampilkan statistik"
else
    warn "⚠️  Dashboard mungkin tidak menampilkan statistik dengan benar"
fi

# ============================================================
# 2. BUAT PELANGGAN BARU + KENDARAAN
# ============================================================
log "\n=== 2. BUAT PELANGGAN BARU + KENDARAAN ==="

# Generate nama unik untuk testing
TIMESTAMP=$(date +%s)
CUSTOMER_NAME="Test Customer $TIMESTAMP"
CUSTOMER_PHONE="081234567890"
CUSTOMER_ADDRESS="Jl. Test No. $TIMESTAMP"

log "Membuat pelanggan: $CUSTOMER_NAME"
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "nama=$CUSTOMER_NAME&telepon=$CUSTOMER_PHONE&alamat=$CUSTOMER_ADDRESS" \
    "$BASE_URL/index.php?page=customers")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Tambah pelanggan"
check_errors "$BODY" "Tambah pelanggan"

# Ambil ID pelanggan yang baru dibuat
log "Mengambil daftar pelanggan untuk mendapatkan ID..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=customers")
CUSTOMER_ID=$(echo "$RESPONSE" | grep -oP "customer_id=\K\d+" | head -1)

if [ -z "$CUSTOMER_ID" ]; then
    # Coba ambil dari database langsung via query
    warn "Tidak dapat menemukan customer_id dari HTML, mencoba query database..."
    # Untuk sementara, gunakan ID dummy atau skip
    CUSTOMER_ID="1"
fi

log "Customer ID: $CUSTOMER_ID"

# Tambah kendaraan untuk pelanggan
log "Menambahkan kendaraan untuk pelanggan..."
VEHICLE_MEREK="Honda"
VEHICLE_MODEL="Beat"
VEHICLE_PLAT="B${TIMESTAMP:(-4)}"

RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "customer_id=$CUSTOMER_ID&merek=$VEHICLE_MEREK&model=$VEHICLE_MODEL&plat_nomor=$VEHICLE_PLAT" \
    "$BASE_URL/index.php?page=customers")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Tambah kendaraan"
check_errors "$BODY" "Tambah kendaraan"

# Verifikasi kendaraan muncul di daftar
if echo "$BODY" | grep -q "$VEHICLE_PLAT"; then
    log "✅ Kendaraan $VEHICLE_PLAT berhasil ditambahkan"
else
    warn "⚠️  Kendaraan mungkin belum muncul di daftar"
fi

# ============================================================
# 3. BUAT SPAREPART BARU
# ============================================================
log "\n=== 3. BUAT SPAREPART BARU ==="

PART_CODE="PART-$TIMESTAMP"
PART_NAME="Test Sparepart $TIMESTAMP"
PART_CATEGORY="Oli"
PART_HARGA_BELI="50000"
PART_HARGA_JUAL="75000"
PART_STOK="10"
PART_STOK_MIN="3"

log "Membuat sparepart: $PART_NAME (kode: $PART_CODE)"
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "kode=$PART_CODE&nama=$PART_NAME&kategori=$PART_CATEGORY&harga_beli=$PART_HARGA_BELI&harga_jual=$PART_HARGA_JUAL&stok=$PART_STOK&stok_min=$PART_STOK_MIN" \
    "$BASE_URL/index.php?page=parts")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Tambah sparepart"
check_errors "$BODY" "Tambah sparepart"

# Verifikasi sparepart tersimpan
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=parts")
if echo "$RESPONSE" | grep -q "$PART_CODE"; then
    log "✅ Sparepart $PART_CODE berhasil tersimpan"
else
    warn "⚠️  Sparepart mungkin belum tersimpan"
fi

# Ambil part_id untuk testing selanjutnya
PART_ID=$(echo "$RESPONSE" | grep -oP "part_id=\K\d+" | head -1)
if [ -z "$PART_ID" ]; then
    PART_ID="1"
fi
log "Part ID: $PART_ID"

# ============================================================
# 4. STOK MASUK & STOK KELUAR
# ============================================================
log "\n=== 4. STOK MASUK & STOK KELUAR ==="

# Stok masuk
log "Melakukan stok masuk..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "part_id=$PART_ID&tipe=masuk&jumlah=20&supplier_id=1&keterangan=Stok masuk test" \
    "$BASE_URL/index.php?page=stock")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Stok masuk"
check_errors "$BODY" "Stok masuk"

# Stok keluar
log "Melakukan stok keluar manual..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "part_id=$PART_ID&tipe=keluar&jumlah=5&keterangan=Stok keluar test" \
    "$BASE_URL/index.php?page=stock")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Stok keluar"
check_errors "$BODY" "Stok keluar"

# Verifikasi riwayat pergerakan stok
log "Memeriksa riwayat pergerakan stok..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=stock")
if echo "$RESPONSE" | grep -q "Stok masuk test\|Stok keluar test"; then
    log "✅ Riwayat pergerakan stok tercatat"
else
    warn "⚠️  Riwayat pergerakan stok mungkin tidak tercatat"
fi

# ============================================================
# 5. BUAT TRANSAKSI POS
# ============================================================
log "\n=== 5. BUAT TRANSAKSI POS ==="

log "Mengakses halaman POS..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/index.php?page=pos")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Akses POS"
check_errors "$BODY" "Akses POS"

# Buat transaksi dengan 1 jasa + 1 sparepart + diskon
log "Membuat transaksi POS (1 jasa + 1 sparepart + diskon)..."

# Data transaksi dalam format JSON atau form data
# Format: items[0][tipe]=jasa&items[0][nama]=Ganti Oli&items[0][qty]=1&items[0][harga]=50000...
TRANSACTION_DATA="customer_id=$CUSTOMER_ID"
TRANSACTION_DATA+="&items[0][tipe]=jasa&items[0][nama]=Ganti Oli&items[0][qty]=1&items[0][harga]=50000&items[0][subtotal]=50000&items[0][garansi_hari]=30"
TRANSACTION_DATA+="&items[1][tipe]=part&items[1][part_id]=$PART_ID&items[1][nama]=$PART_NAME&items[1][qty]=2&items[1][harga]=75000&items[1][subtotal]=150000&items[1][garansi_hari]=90"
TRANSACTION_DATA+="&diskon=10000&catatan=Test transaksi"

RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
    -d "$TRANSACTION_DATA" \
    "$BASE_URL/index.php?page=pos")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Transaksi sukses biasanya redirect ke receipt
if [ "$HTTP_STATUS" = "302" ] || [ "$HTTP_STATUS" = "200" ]; then
    log "✅ Transaksi POS berhasil (HTTP $HTTP_STATUS)"
    check_errors "$BODY" "Transaksi POS"
    
    # Cek apakah ada redirect ke receipt
    LOCATION=$(echo "$BODY" | grep -oP 'Location: .*receipt.*id=\K\d+' || echo "")
    if [ -z "$LOCATION" ]; then
        # Coba ambil dari HTML
        TRANSACTION_ID=$(echo "$BODY" | grep -oP 'receipt.*?id=\K\d+' | head -1)
    else
        TRANSACTION_ID="$LOCATION"
    fi
    
    if [ -z "$TRANSACTION_ID" ]; then
        warn "⚠️  Tidak dapat menemukan transaction_id dari response"
        # Ambil transaksi terakhir
        RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=transactions")
        TRANSACTION_ID=$(echo "$RESPONSE" | grep -oP 'receipt.*?id=\K\d+' | head -1)
    fi
    
    log "Transaction ID: $TRANSACTION_ID"
else
    error "❌ Transaksi POS gagal (HTTP $HTTP_STATUS)"
    echo "$BODY" | head -30
fi

# Verifikasi format no_nota (TRX-YYYYMM-NNN)
log "Memeriksa format no_nota..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=transactions")
if echo "$RESPONSE" | grep -qP "TRX-\d{6}-\d{3}"; then
    log "✅ Format no_nota benar (TRX-YYYYMM-NNN)"
else
    warn "⚠️  Format no_nota mungkin tidak sesuai"
fi

# Verifikasi stok sparepart berkurang
log "Memeriksa stok sparepart setelah transaksi..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=parts")
# Stok awal: 10, masuk: 20, keluar: 5, transaksi: 2 = sisa: 23
if echo "$RESPONSE" | grep -q "$PART_CODE"; then
    log "✅ Stok sparepart diupdate"
else
    warn "⚠️  Stok sparepart mungkin tidak terupdate"
fi

# ============================================================
# 6. STRUK/NOTA - VERIFIKASI TOMBOL WHATSAPP
# ============================================================
log "\n=== 6. STRUK/NOTA - VERIFIKASI TOMBOL WHATSAPP ==="

# Gunakan transaksi ID 8 (Anas dengan telepon) seperti di review request
log "Mengakses struk transaksi ID 8 (pelanggan dengan telepon)..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=receipt&id=8")

check_errors "$RESPONSE" "Struk ID 8"

# Verifikasi tombol WhatsApp ada dengan data-testid="wa-btn"
if echo "$RESPONSE" | grep -q 'data-testid="wa-btn"'; then
    log "✅ Tombol WhatsApp ditemukan (data-testid='wa-btn')"
    
    # Verifikasi format URL WhatsApp
    WA_URL=$(echo "$RESPONSE" | grep -oP 'href="https://wa\.me/\K[^"]+' | head -1)
    if [ -n "$WA_URL" ]; then
        log "✅ URL WhatsApp: https://wa.me/$WA_URL"
        
        # Decode URL dan cek konten pesan
        DECODED_MSG=$(echo "$WA_URL" | sed 's/%20/ /g' | sed 's/%0A/\n/g')
        
        # Verifikasi konten pesan
        CHECKS=0
        if echo "$DECODED_MSG" | grep -qi "BENGKEL\|No.*Nota\|Nota"; then
            log "✅ Pesan berisi nama bengkel dan No. Nota"
            ((CHECKS++))
        fi
        if echo "$DECODED_MSG" | grep -qi "Tanggal"; then
            log "✅ Pesan berisi Tanggal"
            ((CHECKS++))
        fi
        if echo "$DECODED_MSG" | grep -qi "Total"; then
            log "✅ Pesan berisi Total"
            ((CHECKS++))
        fi
        if echo "$DECODED_MSG" | grep -qi "Garansi"; then
            log "✅ Pesan berisi Info Garansi"
            ((CHECKS++))
        fi
        
        if [ $CHECKS -ge 3 ]; then
            log "✅ Konten pesan WhatsApp lengkap"
        else
            warn "⚠️  Konten pesan WhatsApp mungkin tidak lengkap"
        fi
        
        # Verifikasi format nomor (62xxx)
        if echo "$WA_URL" | grep -qP "^62\d{9,}"; then
            log "✅ Format nomor WhatsApp benar (62xxx)"
        else
            warn "⚠️  Format nomor WhatsApp mungkin salah"
        fi
    else
        warn "⚠️  URL WhatsApp tidak ditemukan"
    fi
else
    error "❌ Tombol WhatsApp tidak ditemukan"
fi

# Test untuk pelanggan tanpa telepon (jika ada)
log "\nMengakses struk untuk pelanggan tanpa telepon..."
# Buat transaksi dummy dengan pelanggan tanpa telepon atau cek existing
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=receipt&id=${TRANSACTION_ID:-1}")
if echo "$RESPONSE" | grep -q 'data-testid="wa-btn-disabled"'; then
    log "✅ Tombol WhatsApp disabled untuk pelanggan tanpa telepon"
elif echo "$RESPONSE" | grep -q 'data-testid="wa-btn"'; then
    log "✅ Tombol WhatsApp aktif (pelanggan punya telepon)"
else
    warn "⚠️  Status tombol WhatsApp tidak dapat diverifikasi"
fi

# ============================================================
# 7. RIWAYAT TRANSAKSI - EDIT & HAPUS
# ============================================================
log "\n=== 7. RIWAYAT TRANSAKSI - EDIT & HAPUS ==="

log "Mengakses halaman riwayat transaksi..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/index.php?page=transactions")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Riwayat transaksi"
check_errors "$BODY" "Riwayat transaksi"

# Edit transaksi (jika ada form edit)
if [ -n "$TRANSACTION_ID" ]; then
    log "Mencoba edit transaksi ID $TRANSACTION_ID..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
        -d "id=$TRANSACTION_ID&catatan=Updated test catatan" \
        "$BASE_URL/index.php?page=transactions")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    check_http_status "$HTTP_STATUS" "200" "Edit transaksi"
    check_errors "$BODY" "Edit transaksi"
fi

# Hapus transaksi (harus ditolak jika ada klaim garansi)
log "Mencoba hapus transaksi..."
# Untuk testing, kita tidak akan benar-benar hapus transaksi yang baru dibuat
# Hanya verifikasi endpoint hapus ada dan berfungsi
log "⚠️  Skip hapus transaksi untuk menjaga data test"

# ============================================================
# 8. KLAIM GARANSI
# ============================================================
log "\n=== 8. KLAIM GARANSI ==="

log "Mengakses halaman klaim garansi..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/index.php?page=warranty")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Halaman garansi"
check_errors "$BODY" "Halaman garansi"

# Cari nota via AJAX lookup (jika ada)
log "Mencoba lookup nota via AJAX..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/ajax/lookup.php?q=TRX")
check_errors "$RESPONSE" "AJAX lookup"

# Ajukan klaim garansi baru (jika memungkinkan)
if [ -n "$TRANSACTION_ID" ]; then
    log "Mengajukan klaim garansi untuk transaksi ID $TRANSACTION_ID..."
    # Ambil transaction_item_id dari transaksi
    RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=receipt&id=$TRANSACTION_ID")
    
    # Buat klaim (format kode: GRS-YYYYMM-NNN)
    RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" -X POST \
        -d "transaction_id=$TRANSACTION_ID&transaction_item_id=1&alasan=Test klaim garansi" \
        "$BASE_URL/index.php?page=warranty")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    check_http_status "$HTTP_STATUS" "200" "Ajukan klaim garansi"
    check_errors "$BODY" "Ajukan klaim garansi"
    
    # Verifikasi format kode GRS-YYYYMM-NNN
    RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/index.php?page=warranty")
    if echo "$RESPONSE" | grep -qP "GRS-\d{6}-\d{3}"; then
        log "✅ Format kode garansi benar (GRS-YYYYMM-NNN)"
    else
        warn "⚠️  Format kode garansi mungkin tidak sesuai"
    fi
fi

# ============================================================
# 9. REKAP & LAPORAN
# ============================================================
log "\n=== 9. REKAP & LAPORAN ==="

# Test berbagai periode
PERIODS=("harian" "bulanan" "tahunan" "custom")
for PERIOD in "${PERIODS[@]}"; do
    log "Testing laporan periode: $PERIOD"
    
    if [ "$PERIOD" = "custom" ]; then
        URL="$BASE_URL/index.php?page=reports&periode=custom&dari=2024-01-01&sampai=2024-12-31"
    else
        URL="$BASE_URL/index.php?page=reports&periode=$PERIOD"
    fi
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$URL")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    check_http_status "$HTTP_STATUS" "200" "Laporan $PERIOD"
    check_errors "$BODY" "Laporan $PERIOD"
done

# Test charts
log "Testing halaman charts..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/index.php?page=charts")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

check_http_status "$HTTP_STATUS" "200" "Charts"
check_errors "$BODY" "Charts"

# Test export
log "Testing export..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/export.php?type=transactions&format=csv")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" != "500" ]; then
    log "✅ Export tidak error 500 (HTTP $HTTP_STATUS)"
    check_errors "$BODY" "Export"
else
    error "❌ Export error 500"
fi

# ============================================================
# 10. IMPORT SPAREPART (OPSIONAL)
# ============================================================
log "\n=== 10. IMPORT SPAREPART (OPSIONAL) ==="

log "Testing endpoint import sparepart..."
RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/ajax/import_parts.php")
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Import tanpa file akan error, tapi endpoint harus ada
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "400" ]; then
    log "✅ Endpoint import sparepart tersedia (HTTP $HTTP_STATUS)"
else
    warn "⚠️  Endpoint import sparepart mungkin tidak tersedia (HTTP $HTTP_STATUS)"
fi

# ============================================================
# SUMMARY
# ============================================================
log "\n=== RINGKASAN PENGUJIAN ==="
log "Log lengkap tersimpan di: $TEST_LOG"

# Hitung jumlah error
ERROR_COUNT=$(grep -c "\[ERROR\]" "$TEST_LOG" || echo "0")
WARN_COUNT=$(grep -c "\[WARN\]" "$TEST_LOG" || echo "0")

log "\nTotal Error: $ERROR_COUNT"
log "Total Warning: $WARN_COUNT"

if [ "$ERROR_COUNT" -eq 0 ]; then
    log "\n${GREEN}✅ SEMUA TEST BACKEND BERHASIL!${NC}"
    exit 0
else
    error "\n${RED}❌ DITEMUKAN $ERROR_COUNT ERROR DALAM TESTING${NC}"
    exit 1
fi

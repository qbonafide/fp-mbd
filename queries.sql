-- ============================================================
-- FILE: queries.sql
-- Pekerjaan 3: Query Kompleks & Optimasi Index
-- Peran: Data Analyst (Agil)
-- Database: fp_rental_kendaraan (MySQL/MariaDB)
-- ============================================================

-- ============================================================
-- BAGIAN A: PEMBUATAN INDEX PADA KOLOM-KOLOM KUNCI
-- ============================================================
-- Index berikut diterapkan pada kolom yang sering di-JOIN
-- atau di-WHERE untuk mempercepat eksekusi query kompleks.

-- 1. Index pada NIK di tabel daftar_hitam
--    Alasan: Kolom nik (VARCHAR) sering di-JOIN dengan
--    tabel pelanggan untuk cross-check blacklist.
CREATE INDEX IF NOT EXISTS idx_daftar_hitam_nik
    ON daftar_hitam(nik);

-- 2. Index pada status_sewa di tabel kontrak_sewa
--    Alasan: Hampir semua query memfilter berdasarkan
--    status_sewa ('Aktif', 'Terlambat', dll) dari 200k data.
CREATE INDEX IF NOT EXISTS idx_kontrak_sewa_status
    ON kontrak_sewa(status_sewa);

-- 3. Index pada status_kendaraan di tabel kendaraan
--    Alasan: Query monitoring kendaraan sering memfilter
--    berdasarkan status operasional kendaraan.
CREATE INDEX IF NOT EXISTS idx_kendaraan_status
    ON kendaraan(status_kendaraan);

-- 4. Composite Index pada (id_kendaraan, waktu_log) di pelacakan_lokasi
--    Alasan: Subquery GROUP BY + MAX memerlukan akses efisien
--    ke log pelacakan terbaru per kendaraan dari 500k data.
--    Index komposit memungkinkan "Using index for group-by".
CREATE INDEX IF NOT EXISTS idx_pelacakan_kendaraan_waktu
    ON pelacakan_lokasi(id_kendaraan, waktu_log);

-- 5. Index pada id_sewa di tabel pelanggaran_geofence
--    Alasan: Mempercepat JOIN antara pelanggaran geofence
--    dengan kontrak sewa saat membuat laporan agregat.
CREATE INDEX IF NOT EXISTS idx_pelanggaran_geofence_sewa
    ON pelanggaran_geofence(id_sewa);


-- ============================================================
-- BAGIAN B: 3 QUERY KOMPLEKS
-- ============================================================

-- ============================================================
-- QUERY 1: DETEKSI KENDARAAN OFF-GPS
-- ============================================================
-- Tujuan : Mendeteksi kendaraan dengan status sewa aktif/
--          terlambat yang kehilangan sinyal GPS (status 'Hilang')
--          atau tidak mengirimkan log pelacakan selama >24 jam.
-- Tabel  : kontrak_sewa, pelanggan, kendaraan, pelacakan_lokasi
-- Teknik : Subquery bertingkat + LEFT JOIN + TIMESTAMPDIFF
-- ============================================================

SELECT
    k.id_kendaraan,
    k.plat_nomor,
    k.merk,
    k.model,
    ks.id_sewa,
    ks.status_sewa,
    p.nama_depan,
    p.nama_belakang,
    p.nik,
    p.no_telp,
    pl.waktu_log         AS terakhir_kirim_sinyal,
    pl.status_sinyal,
    pl.latitude,
    pl.longitude,
    TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) AS jam_sejak_sinyal_terakhir
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN (
    -- Subquery: Ambil data log pelacakan TERBARU per kendaraan
    SELECT pl1.id_kendaraan,
           pl1.waktu_log,
           pl1.status_sinyal,
           pl1.latitude,
           pl1.longitude
    FROM pelacakan_lokasi pl1
    INNER JOIN (
        -- Subquery dalam: Cari waktu log maksimal per kendaraan
        SELECT id_kendaraan, MAX(waktu_log) AS max_waktu
        FROM pelacakan_lokasi
        GROUP BY id_kendaraan
    ) pl2 ON pl1.id_kendaraan = pl2.id_kendaraan
         AND pl1.waktu_log = pl2.max_waktu
) pl ON k.id_kendaraan = pl.id_kendaraan
WHERE ks.status_sewa IN ('Aktif', 'Terlambat')
  AND (
      pl.status_sinyal = 'Hilang'
      OR pl.waktu_log IS NULL
      OR TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) > 24
  )
LIMIT 20;


-- ============================================================
-- QUERY 2: LAPORAN PELANGGARAN GEOFENCE
-- ============================================================
-- Tujuan : Menyajikan rekapitulasi pelanggan dengan sewa aktif
--          yang memiliki >=2 pelanggaran batas geofence.
-- Tabel  : pelanggaran_geofence, kontrak_sewa, pelanggan,
--          kendaraan, konfigurasi_geofence
-- Teknik : Multi-JOIN + GROUP BY + HAVING + GROUP_CONCAT
--          + Fungsi Agregat (COUNT, MAX)
-- ============================================================

SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.no_telp,
    k.plat_nomor,
    k.merk,
    k.model,
    ks.id_sewa,
    ks.status_sewa,
    ks.tanggal_ambil,
    kg.radius_km                              AS batas_geofence_km,
    COUNT(pg.id_pelanggaran)                  AS total_pelanggaran,
    MAX(pg.jarak_pelanggaran_km)              AS jarak_terjauh_km,
    MAX(pg.waktu_pelanggaran)                 AS pelanggaran_terakhir,
    GROUP_CONCAT(
        DISTINCT pg.status_penanganan
        ORDER BY pg.status_penanganan
    ) AS status_penanganan_list
FROM pelanggaran_geofence pg
JOIN kontrak_sewa ks      ON pg.id_sewa      = ks.id_sewa
JOIN pelanggan p           ON ks.id_pelanggan = p.id_pelanggan
JOIN kendaraan k           ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN konfigurasi_geofence kg ON ks.id_sewa = kg.id_sewa
WHERE ks.status_sewa IN ('Aktif', 'Terlambat', 'Macet-Hukum')
GROUP BY
    p.nik, nama_pelanggan, p.no_telp,
    k.plat_nomor, k.merk, k.model,
    ks.id_sewa, ks.status_sewa, ks.tanggal_ambil,
    kg.radius_km
HAVING COUNT(pg.id_pelanggaran) >= 2
ORDER BY total_pelanggaran DESC
LIMIT 20;

-- ============================================================
-- QUERY 3: CROSS-CHECK NIK DENGAN DATABASE KOMUNITAS (BLACKLIST)
-- ============================================================
-- Tujuan : Mencocokkan NIK pelanggan sewa aktif/terlambat/dipesan
--          dengan database daftar hitam komunitas persewaan untuk
--          mendeteksi potensi fraud atau risiko tinggi.
-- Tabel  : pelanggan, kontrak_sewa, kendaraan, daftar_hitam,
--          komunitas_rental
-- Teknik : Multi-JOIN (5 tabel) + Filter pada kolom ENUM
--          + ORDER BY pada kolom DATE
-- ============================================================

SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun,
    ks.id_sewa,
    ks.status_sewa,
    k.plat_nomor,
    k.status_kendaraan,
    dh.nama_lengkap     AS nama_di_blacklist,
    dh.jenis_pelanggaran,
    dh.tanggal_kejadian,
    dh.status_verifikasi,
    kr.nama_rental      AS rental_pelapor,
    kr.kota             AS kota_rental_pelapor
FROM pelanggan p
JOIN kontrak_sewa ks    ON p.id_pelanggan = ks.id_pelanggan
JOIN kendaraan k        ON ks.id_kendaraan = k.id_kendaraan
JOIN daftar_hitam dh    ON p.nik = dh.nik
JOIN komunitas_rental kr ON dh.id_rental_pelapor = kr.id_rental
WHERE ks.status_sewa IN ('Aktif', 'Terlambat', 'Dipesan')
  AND dh.status_verifikasi = 'Terverifikasi'
ORDER BY dh.tanggal_kejadian DESC
LIMIT 20;


-- ============================================================
-- BAGIAN C: SKENARIO DATA INPUT
-- ============================================================
-- Membuktikan bahwa data berhasil di-insert dengan menampilkan:
--   1. Satu Record Lengkap (semua kolom terisi)
--   2. Record dengan Kolom NULL
-- ============================================================


-- ############################################################
-- SKENARIO 1: Tabel kontrak_sewa
-- ############################################################

-- Record Lengkap (Kontrak Selesai - semua kolom terisi)
SELECT * FROM kontrak_sewa
WHERE tanggal_kembali_aktual IS NOT NULL
  AND total_harga IS NOT NULL
  AND status_sewa = 'Selesai'
LIMIT 1;

-- Record dengan Kolom NULL (Kontrak Aktif - belum dikembalikan)
SELECT * FROM kontrak_sewa
WHERE tanggal_kembali_aktual IS NULL
  AND status_sewa = 'Aktif'
LIMIT 1;
-- → tanggal_kembali_aktual = NULL karena kendaraan belum dikembalikan
-- → Dari 200.000 kontrak, 73.777 (36.9%) memiliki NULL di kolom ini


-- ############################################################
-- SKENARIO 2: Tabel konfigurasi_geofence
-- ############################################################

-- Record Lengkap (radius dan status aktif terisi)
SELECT * FROM konfigurasi_geofence LIMIT 1;
-- → batas_poligon = NULL pada seluruh 200.000 record
-- → Sistem menggunakan metode radius lingkaran, bukan poligon
-- → Kolom batas_poligon disediakan untuk pengembangan masa depan


-- ############################################################
-- SKENARIO 3: Tabel pelanggan
-- ############################################################

-- Record Lengkap (semua kolom NOT NULL - tidak ada kolom nullable)
SELECT * FROM pelanggan LIMIT 1;
-- → Tabel pelanggan tidak memiliki kolom nullable
-- → Semua kolom wajib diisi sesuai business rule



-- ############################################################
-- RINGKASAN SKENARIO DATA
-- ############################################################
-- Tabel             | Kolom Nullable              | NULL  | Total   | %
-- ------------------+-----------------------------+-------+---------+------
-- kontrak_sewa      | tanggal_kembali_aktual      | 73777 | 200000  | 36.9%
-- konfigurasi_geo.  | batas_poligon               | 200000| 200000  | 100%
-- pelanggan         | (tidak ada kolom nullable)  | 0     | 200000  | 0%


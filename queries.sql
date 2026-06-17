-- ============================================================
-- FILE: queries.sql
-- Pekerjaan 3: Query Kompleks & Optimasi Index
-- Peran: Data Analyst (Agil)
-- Database: fp_rental_kendaraan (MySQL/MariaDB)
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

-- ============================================
-- OPTIMASI QUERY 1: Deteksi Kendaraan Off-GPS
-- ============================================

-- 1. Buat index untuk optimasi
CREATE INDEX idx_pelacakan_kendaraan_waktu 
ON pelacakan_lokasi(id_kendaraan, waktu_log DESC);

CREATE INDEX idx_kontrak_sewa_status_kendaraan 
ON kontrak_sewa(status_sewa, id_kendaraan);

CREATE INDEX idx_pelacakan_status_sinyal 
ON pelacakan_lokasi(status_sinyal);

-- 2. Query yang dioptimasi dengan CTE dan Window Function
WITH latest_location AS (
    SELECT 
        id_kendaraan,
        latitude,
        longitude,
        waktu_log,
        status_sinyal,
        ROW_NUMBER() OVER (PARTITION BY id_kendaraan ORDER BY waktu_log DESC) AS rn
    FROM pelacakan_lokasi
    WHERE status_sinyal = 'Hilang' 
       OR waktu_log < DATE_SUB(NOW(), INTERVAL 24 HOUR)
),
active_rentals AS (
    SELECT 
        ks.id_sewa,
        ks.id_kendaraan,
        ks.status_sewa,
        ks.tanggal_ambil,
        ks.tanggal_kembali_rencana,
        p.nik,
        p.nama_depan,
        p.nama_belakang,
        p.no_telp
    FROM kontrak_sewa ks
    JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
    WHERE ks.status_sewa IN ('Aktif', 'Terlambat')
)
SELECT 
    k.id_kendaraan,
    k.plat_nomor,
    k.merk,
    k.model,
    ar.id_sewa,
    ar.status_sewa,
    ar.tanggal_ambil,
    ar.tanggal_kembali_rencana,
    ar.nik,
    CONCAT(ar.nama_depan, ' ', ar.nama_belakang) AS nama_pelanggan,
    ar.no_telp,
    pl.latitude,
    pl.longitude,
    pl.waktu_log AS last_location_time,
    pl.status_sinyal,
    TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) AS jam_tidak_terdeteksi
FROM kendaraan k
INNER JOIN active_rentals ar ON k.id_kendaraan = ar.id_kendaraan
LEFT JOIN latest_location pl ON k.id_kendaraan = pl.id_kendaraan AND pl.rn = 1
WHERE pl.status_sinyal = 'Hilang' 
   OR pl.waktu_log IS NULL 
   OR TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) > 24
ORDER BY jam_tidak_terdeteksi DESC
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

-- ============================================
-- OPTIMASI QUERY 2: Laporan Pelanggaran Geofence
-- ============================================

-- 1. Buat index untuk optimasi
CREATE INDEX idx_pelanggaran_sewa_waktu 
ON pelanggaran_geofence(id_sewa, waktu_pelanggaran DESC);

CREATE INDEX idx_kontrak_sewa_status 
ON kontrak_sewa(status_sewa);

CREATE INDEX idx_pelanggaran_jarak 
ON pelanggaran_geofence(jarak_pelanggaran_km);

-- 2. Buat materialized view untuk ringkasan pelanggaran
CREATE TABLE ringkasan_pelanggaran_geofence_all (
    id_sewa INT PRIMARY KEY,
    total_pelanggaran INT DEFAULT 0,
    jarak_terjauh_km DECIMAL(10,2) DEFAULT 0,
    pelanggaran_terakhir DATETIME,
    status_penanganan_list TEXT,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_total_pelanggaran (total_pelanggaran DESC),
    INDEX idx_pelanggaran_terakhir (pelanggaran_terakhir DESC)
);

-- 3. Stored Procedure untuk update ringkasan (dijalankan periodik)
DELIMITER //
CREATE PROCEDURE update_ringkasan_pelanggaran_all()
BEGIN
    REPLACE INTO ringkasan_pelanggaran_geofence_all 
        (id_sewa, total_pelanggaran, jarak_terjauh_km, pelanggaran_terakhir, status_penanganan_list)
    SELECT 
        id_sewa,
        COUNT(id_pelanggaran) AS total_pelanggaran,
        MAX(jarak_pelanggaran_km) AS jarak_terjauh_km,
        MAX(waktu_pelanggaran) AS pelanggaran_terakhir,
        GROUP_CONCAT(DISTINCT status_penanganan ORDER BY status_penanganan) AS status_penanganan_list
    FROM pelanggaran_geofence
    GROUP BY id_sewa
    HAVING COUNT(id_pelanggaran) >= 2;
END //
DELIMITER ;

-- 4. Trigger untuk update otomatis
DELIMITER //
CREATE TRIGGER after_insert_pelanggaran
AFTER INSERT ON pelanggaran_geofence
FOR EACH ROW
BEGIN
    INSERT INTO ringkasan_pelanggaran_geofence_all 
        (id_sewa, total_pelanggaran, jarak_terjauh_km, pelanggaran_terakhir, status_penanganan_list)
    SELECT 
        id_sewa,
        COUNT(id_pelanggaran) AS total_pelanggaran,
        MAX(jarak_pelanggaran_km) AS jarak_terjauh_km,
        MAX(waktu_pelanggaran) AS pelanggaran_terakhir,
        GROUP_CONCAT(DISTINCT status_penanganan ORDER BY status_penanganan) AS status_penanganan_list
    FROM pelanggaran_geofence
    WHERE id_sewa = NEW.id_sewa
    GROUP BY id_sewa
    ON DUPLICATE KEY UPDATE
        total_pelanggaran = VALUES(total_pelanggaran),
        jarak_terjauh_km = VALUES(jarak_terjauh_km),
        pelanggaran_terakhir = VALUES(pelanggaran_terakhir),
        status_penanganan_list = VALUES(status_penanganan_list);
END //
DELIMITER ;

-- 5. Jalankan sekali untuk inisialisasi
CALL update_ringkasan_pelanggaran_all();

-- 6. Query yang dioptimasi menggunakan ringkasan (HASIL SAMA DENGAN ORIGINAL)
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
    kg.radius_km AS batas_geofence_km,
    rpg.total_pelanggaran,
    rpg.jarak_terjauh_km,
    rpg.pelanggaran_terakhir,
    rpg.status_penanganan_list,
    CASE 
        WHEN rpg.total_pelanggaran >= 5 THEN 'KRITIS'
        WHEN rpg.total_pelanggaran >= 3 THEN 'TINGGI'
        WHEN rpg.total_pelanggaran >= 2 THEN 'SEDANG'
        ELSE 'RENDAH'
    END AS tingkat_risiko
FROM ringkasan_pelanggaran_geofence_all rpg
JOIN kontrak_sewa ks ON rpg.id_sewa = ks.id_sewa
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN konfigurasi_geofence kg ON ks.id_sewa = kg.id_sewa
WHERE ks.status_sewa IN ('Aktif', 'Terlambat', 'Macet-Hukum')
ORDER BY rpg.total_pelanggaran DESC, rpg.pelanggaran_terakhir DESC
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

-- ============================================
-- OPTIMASI QUERY 3: Cross-check NIK Blacklist
-- ============================================

-- 1. Buat index untuk optimasi
CREATE INDEX idx_daftar_hitam_nik_status 
ON daftar_hitam(nik, status_verifikasi);

CREATE INDEX idx_daftar_hitam_tanggal 
ON daftar_hitam(tanggal_kejadian DESC);

CREATE INDEX idx_kontrak_sewa_status_pelanggan 
ON kontrak_sewa(status_sewa, id_pelanggan);

CREATE INDEX idx_pelanggan_nik 
ON pelanggan(nik);

-- 2. Query optimasi dengan hasil SAMA PERSIS dengan Original
WITH verified_blacklist AS (
    SELECT 
        nik,
        nama_lengkap,
        jenis_pelanggaran,
        tanggal_kejadian,
        status_verifikasi,
        id_rental_pelapor
    FROM daftar_hitam
    WHERE status_verifikasi = 'Terverifikasi'
)
SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun,
    ks.id_sewa,
    ks.status_sewa,
    k.plat_nomor,
    k.status_kendaraan,
    dh.nama_lengkap AS nama_di_blacklist,
    dh.jenis_pelanggaran,
    dh.tanggal_kejadian,
    dh.status_verifikasi,
    kr.nama_rental AS rental_pelapor,
    kr.kota AS kota_rental_pelapor
FROM pelanggan p
JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
JOIN verified_blacklist dh ON p.nik = dh.nik
JOIN komunitas_rental kr ON dh.id_rental_pelapor = kr.id_rental
WHERE ks.status_sewa IN ('Aktif', 'Terlambat', 'Dipesan')
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


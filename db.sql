-- =========================================================================
-- 1. DATA MASTER
-- =========================================================================

-- Menyimpan data cabang pengelola kendaraan
CREATE TABLE Cabang_Rental (
    id_cabang INT AUTO_INCREMENT PRIMARY KEY,
    nama_cabang VARCHAR(100) NOT NULL,
    alamat TEXT NOT NULL,
    no_telp VARCHAR(15) NOT NULL
);

-- Menyimpan data penyewa
CREATE TABLE Pelanggan (
    id_pelanggan INT AUTO_INCREMENT PRIMARY KEY,
    nik VARCHAR(16) UNIQUE NOT NULL,
    nama_depan VARCHAR(50) NOT NULL,
    nama_belakang VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    no_telp VARCHAR(15) NOT NULL,
    no_sim VARCHAR(50) UNIQUE NOT NULL,
    status_akun ENUM('Aktif', 'Ditangguhkan', 'Diblokir') DEFAULT 'Aktif'
);

-- Menyimpan harga dasar harian dan denda per tipe mobil
CREATE TABLE Kategori_Kendaraan (
    id_kategori INT AUTO_INCREMENT PRIMARY KEY,
    nama_kategori VARCHAR(50) NOT NULL,
    tarif_harian DECIMAL(10,2) NOT NULL,
    denda_keterlambatan_per_jam DECIMAL(10,2) NOT NULL
);

-- Komunitas rental yang berbagi data daftar hitam
CREATE TABLE Komunitas_Rental (
    id_rental INT AUTO_INCREMENT PRIMARY KEY,
    nama_rental VARCHAR(100) NOT NULL,
    kota VARCHAR(50) NOT NULL,
    kontak VARCHAR(50) NOT NULL,
    api_key VARCHAR(100) UNIQUE NOT NULL,
    status_keanggotaan ENUM('Aktif', 'Non-Aktif') DEFAULT 'Aktif',
    tanggal_bergabung DATE NOT NULL
);

-- =========================================================================
-- 2. INVENTARIS & TRANSAKSI OPERASIONAL
-- =========================================================================

-- Kendaraan Fisik
CREATE TABLE Kendaraan (
    id_kendaraan INT AUTO_INCREMENT PRIMARY KEY,
    id_kategori INT NOT NULL,
    id_cabang INT NOT NULL,
    merk VARCHAR(50) NOT NULL,
    model VARCHAR(50) NOT NULL,
    tahun_pembuatan INT NOT NULL,
    plat_nomor VARCHAR(20) UNIQUE NOT NULL,
    kilometer_saat_ini INT NOT NULL DEFAULT 0,
    status_kendaraan ENUM('Tersedia', 'Sedang Disewa', 'Perawatan', 'Hilang', 'Rusak') DEFAULT 'Tersedia',
    FOREIGN KEY (id_kategori) REFERENCES Kategori_Kendaraan(id_kategori) ON DELETE RESTRICT,
    FOREIGN KEY (id_cabang) REFERENCES Cabang_Rental(id_cabang) ON DELETE RESTRICT
);

-- Kontrak Sewa (Transaksi Peminjaman)
CREATE TABLE Kontrak_Sewa (
    id_sewa INT AUTO_INCREMENT PRIMARY KEY,
    id_pelanggan INT NOT NULL,
    id_kendaraan INT NOT NULL,
    tanggal_ambil DATETIME NOT NULL,
    tanggal_kembali_rencana DATETIME NOT NULL,
    tanggal_kembali_aktual DATETIME NULL,
    total_harga DECIMAL(12,2) NULL,
    status_sewa ENUM('Dipesan', 'Aktif', 'Selesai', 'Dibatalkan', 'Terlambat', 'Macet-Hukum') DEFAULT 'Dipesan',
    FOREIGN KEY (id_pelanggan) REFERENCES Pelanggan(id_pelanggan) ON DELETE RESTRICT,
    FOREIGN KEY (id_kendaraan) REFERENCES Kendaraan(id_kendaraan) ON DELETE RESTRICT
);

-- Pembayaran
CREATE TABLE Pembayaran (
    id_pembayaran INT AUTO_INCREMENT PRIMARY KEY,
    id_sewa INT NOT NULL,
    tanggal_bayar DATETIME NOT NULL,
    nominal DECIMAL(12,2) NOT NULL,
    metode_pembayaran ENUM('Kartu Kredit', 'Tunai', 'Transfer Bank', 'E-Wallet', 'QRIS') NOT NULL,
    status_pembayaran ENUM('Lunas', 'Pending', 'Terlambat', 'Menunggak') NOT NULL,
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

-- =========================================================================
-- 3. FITUR KEAMANAN & ANTI-FRAUD
-- =========================================================================

-- Daftar individu yang pernah bermasalah dari seluruh komunitas
CREATE TABLE Daftar_Hitam (
    id_daftar_hitam INT AUTO_INCREMENT PRIMARY KEY,
    nik VARCHAR(16) NOT NULL,
    nama_lengkap VARCHAR(100) NOT NULL,
    url_foto_wajah VARCHAR(255),
    jenis_pelanggaran VARCHAR(100) NOT NULL,
    tanggal_kejadian DATE NOT NULL,
    id_rental_pelapor INT NOT NULL,
    status_verifikasi ENUM('Menunggu', 'Terverifikasi') DEFAULT 'Menunggu',
    FOREIGN KEY (id_rental_pelapor) REFERENCES Komunitas_Rental(id_rental) ON DELETE RESTRICT
);

-- Penyimpanan dokumen KTP/SIM fisik
CREATE TABLE Dokumen_Jaminan (
    id_dokumen INT AUTO_INCREMENT PRIMARY KEY,
    id_sewa INT NOT NULL,
    jenis_dokumen ENUM('KTP', 'SIM', 'Paspor') NOT NULL,
    nomor_dokumen VARCHAR(50) NOT NULL,
    kondisi_penyimpanan VARCHAR(100) NOT NULL,
    lokasi_loker VARCHAR(50) NOT NULL,
    waktu_serah_terima DATETIME NOT NULL,
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

-- Pelacakan lokasi kendaraan secara real-time
CREATE TABLE Pelacakan_Lokasi (
    id_pelacakan BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_kendaraan INT NOT NULL,
    waktu_log DATETIME NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    kecepatan_kmj INT NOT NULL,
    status_sinyal ENUM('Kuat', 'Lemah', 'Hilang') NOT NULL,
    sumber_data ENUM('GPS', 'GSM', 'SIM_CARD') NOT NULL,
    FOREIGN KEY (id_kendaraan) REFERENCES Kendaraan(id_kendaraan) ON DELETE CASCADE
);

-- Pengaturan radius batas wilayah aman
CREATE TABLE Konfigurasi_Geofence (
    id_geofence INT AUTO_INCREMENT PRIMARY KEY,
    id_sewa INT NOT NULL,
    pusat_latitude DECIMAL(10, 8) NOT NULL,
    pusat_longitude DECIMAL(11, 8) NOT NULL,
    radius_km DECIMAL(5, 2) NOT NULL,
    batas_poligon TEXT,
    status_aktif TINYINT(1) DEFAULT 1,
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

-- Log jika kendaraan keluar dari radius Geofence
CREATE TABLE Pelanggaran_Geofence (
    id_pelanggaran INT AUTO_INCREMENT PRIMARY KEY,
    id_kendaraan INT NOT NULL,
    id_sewa INT NOT NULL,
    waktu_pelanggaran DATETIME NOT NULL,
    lokasi_valid_terakhir VARCHAR(100) NOT NULL,
    lokasi_pelanggaran VARCHAR(100) NOT NULL,
    jarak_pelanggaran_km DECIMAL(5, 2) NOT NULL,
    status_penanganan ENUM('Belum Diproses', 'Diperingatkan', 'Mesin Dimatikan') DEFAULT 'Belum Diproses',
    FOREIGN KEY (id_kendaraan) REFERENCES Kendaraan(id_kendaraan) ON DELETE CASCADE,
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

-- Pencatatan otomatis perilaku mencurigakan
CREATE TABLE Log_Anomali (
    id_anomali BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_sewa INT NOT NULL,
    jenis_anomali VARCHAR(50) NOT NULL, 
    waktu_log DATETIME NOT NULL,
    deskripsi TEXT NOT NULL,
    skor_risiko INT NOT NULL,
    status_tindak_lanjut VARCHAR(50) DEFAULT 'Terbuka',
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

-- Dokumentasi kondisi mobil sebelum dan sesudah disewa
CREATE TABLE Inspeksi_Kendaraan (
    id_inspeksi INT AUTO_INCREMENT PRIMARY KEY,
    id_sewa INT NOT NULL,
    tipe_inspeksi ENUM('Pra-Sewa', 'Pasca-Sewa') NOT NULL,
    waktu_inspeksi DATETIME NOT NULL,
    url_foto_1 VARCHAR(255),
    url_foto_2 VARCHAR(255),
    deskripsi_kondisi TEXT NOT NULL,
    id_petugas INT NOT NULL,
    hash_dokumen VARCHAR(255) NOT NULL,
    FOREIGN KEY (id_sewa) REFERENCES Kontrak_Sewa(id_sewa) ON DELETE CASCADE
);

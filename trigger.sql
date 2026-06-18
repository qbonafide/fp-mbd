USE fp_rental_kendaraan;

DROP TRIGGER IF EXISTS trg_after_pelanggaran_geofence_insert;

DELIMITER $$

CREATE TRIGGER trg_after_pelanggaran_geofence_insert
AFTER INSERT ON Pelanggaran_Geofence
FOR EACH ROW
BEGIN
    DECLARE v_total_pelanggaran_sewa INT DEFAULT 0;
    DECLARE v_total_transaksi_pelanggan INT DEFAULT 0;
    DECLARE v_total_pelanggaran_pelanggan INT DEFAULT 0;
    DECLARE v_skor_risiko INT DEFAULT 0;

    DECLARE v_id_pelanggan INT;
    DECLARE v_nik VARCHAR(16);
    DECLARE v_nama_lengkap VARCHAR(100);
    DECLARE v_id_rental_pelapor INT DEFAULT NULL;

    -- Ambil data pelanggan berdasarkan kontrak sewa yang sedang mengalami pelanggaran
    SELECT 
        p.id_pelanggan,
        p.nik,
        LEFT(CONCAT(p.nama_depan, ' ', p.nama_belakang), 100)
    INTO 
        v_id_pelanggan,
        v_nik,
        v_nama_lengkap
    FROM Kontrak_Sewa ks
    JOIN Pelanggan p ON ks.id_pelanggan = p.id_pelanggan
    WHERE ks.id_sewa = NEW.id_sewa;

    -- Hitung total pelanggaran geofence pada transaksi/kontrak sewa yang sama
    SELECT COUNT(*)
    INTO v_total_pelanggaran_sewa
    FROM Pelanggaran_Geofence
    WHERE id_sewa = NEW.id_sewa;

    -- Hitung total transaksi/sewa yang pernah dilakukan pelanggan ini
    SELECT COUNT(*)
    INTO v_total_transaksi_pelanggan
    FROM Kontrak_Sewa
    WHERE id_pelanggan = v_id_pelanggan;

    -- Hitung total pelanggaran geofence pelanggan dari seluruh transaksi sewanya
    SELECT COUNT(*)
    INTO v_total_pelanggaran_pelanggan
    FROM Pelanggaran_Geofence pg
    JOIN Kontrak_Sewa ks ON pg.id_sewa = ks.id_sewa
    WHERE ks.id_pelanggan = v_id_pelanggan;

    -- Hitung skor risiko dasar berdasarkan jarak pelanggaran
    SET v_skor_risiko =
        CASE
            WHEN NEW.jarak_pelanggaran_km >= 50 THEN 90
            WHEN NEW.jarak_pelanggaran_km >= 25 THEN 70
            WHEN NEW.jarak_pelanggaran_km >= 10 THEN 50
            ELSE 30
        END;

    -- Tambahan skor berdasarkan jumlah pelanggaran pada transaksi saat ini
    SET v_skor_risiko = v_skor_risiko + (v_total_pelanggaran_sewa * 5);

    -- Tambahan skor kecil berdasarkan riwayat pelanggaran pelanggan di semua transaksi
    SET v_skor_risiko = v_skor_risiko + (v_total_pelanggaran_pelanggan * 2);

    -- Batas maksimal skor risiko adalah 100
    IF v_skor_risiko > 100 THEN
        SET v_skor_risiko = 100;
    END IF;

    -- Catat anomali otomatis ke tabel Log_Anomali
    INSERT INTO Log_Anomali (
        id_sewa,
        jenis_anomali,
        waktu_log,
        deskripsi,
        skor_risiko,
        status_tindak_lanjut
    )
    VALUES (
        NEW.id_sewa,
        'Pelanggaran Geofence',
        NEW.waktu_pelanggaran,
        CONCAT(
            'Pelanggaran geofence terdeteksi otomatis. Kendaraan ID ',
            NEW.id_kendaraan,
            ' keluar dari batas wilayah sejauh ',
            NEW.jarak_pelanggaran_km,
            ' km. Total pelanggaran pada transaksi sewa ini: ',
            v_total_pelanggaran_sewa,
            '. Total transaksi pelanggan: ',
            v_total_transaksi_pelanggan,
            '. Total pelanggaran pelanggan dari seluruh transaksi: ',
            v_total_pelanggaran_pelanggan,
            '. Lokasi valid terakhir: ',
            NEW.lokasi_valid_terakhir,
            '. Lokasi pelanggaran: ',
            NEW.lokasi_pelanggaran,
            '. Status penanganan: ',
            NEW.status_penanganan
        ),
        v_skor_risiko,
        CASE
            WHEN v_total_pelanggaran_pelanggan >= 5 THEN 'Masuk Blacklist'
            WHEN v_skor_risiko >= 90 THEN 'Prioritas Tinggi'
            WHEN v_skor_risiko >= 70 THEN 'Perlu Ditinjau'
            ELSE 'Terbuka'
        END
    );

    -- Jika pelanggaran berat, berulang dalam satu transaksi, atau riwayat pelanggan buruk
    IF v_skor_risiko >= 90 
       OR v_total_pelanggaran_sewa >= 3
       OR v_total_pelanggaran_pelanggan >= 5 THEN

        UPDATE Kontrak_Sewa
        SET status_sewa = 'Macet-Hukum'
        WHERE id_sewa = NEW.id_sewa;

        UPDATE Pelanggan
        SET status_akun = 'Ditangguhkan'
        WHERE id_pelanggan = v_id_pelanggan;
    END IF;

    -- Jika total pelanggaran pelanggan dari seluruh transaksi sudah mencapai batas blacklist
    IF v_total_pelanggaran_pelanggan >= 5 THEN

        UPDATE Pelanggan
        SET status_akun = 'Diblokir'
        WHERE id_pelanggan = v_id_pelanggan;

        -- Ambil salah satu rental aktif sebagai pelapor blacklist
        SELECT MIN(id_rental)
        INTO v_id_rental_pelapor
        FROM Komunitas_Rental
        WHERE status_keanggotaan = 'Aktif';

        -- Masukkan ke Daftar_Hitam jika belum pernah tercatat sebagai pelanggaran geofence berulang
        IF v_id_rental_pelapor IS NOT NULL
           AND NOT EXISTS (
                SELECT 1
                FROM Daftar_Hitam
                WHERE nik = v_nik
                  AND jenis_pelanggaran = 'Pelanggaran Geofence Berulang'
           ) THEN

            INSERT INTO Daftar_Hitam (
                nik,
                nama_lengkap,
                url_foto_wajah,
                jenis_pelanggaran,
                tanggal_kejadian,
                id_rental_pelapor,
                status_verifikasi
            )
            VALUES (
                v_nik,
                v_nama_lengkap,
                NULL,
                'Pelanggaran Geofence Berulang',
                DATE(NEW.waktu_pelanggaran),
                v_id_rental_pelapor,
                'Menunggu'
            );
        END IF;
    END IF;
END$$

DELIMITER ;

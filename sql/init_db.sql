-- EntropyWatcher Database Schema
-- Auto-generated from entropywatcher.py DDL

CREATE DATABASE IF NOT EXISTS entropywatcher CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE entropywatcher;

-- Main file tracking table
CREATE TABLE IF NOT EXISTS files (
  path VARBINARY(1024) PRIMARY KEY,
  source VARCHAR(16) NULL,
  inode BIGINT UNSIGNED,
  size BIGINT,
  mtime_ns BIGINT,
  sha256 BINARY(32),
  
  start_entropy DOUBLE,
  start_time DATETIME,
  
  prev_entropy DOUBLE,
  prev_time DATETIME,
  
  last_entropy DOUBLE,
  last_time DATETIME,
  
  scans INT DEFAULT 0,
  flagged TINYINT(1) DEFAULT 0,
  note VARCHAR(255),
  missing_since DATETIME NULL,
  
  score_exempt TINYINT(1) DEFAULT 0,
  tags VARCHAR(255) NULL,
  quick_md5 BINARY(16) NULL,
  last_full_verify DATETIME NULL,
  
  INDEX idx_source (source),
  INDEX idx_mtime (mtime_ns),
  INDEX idx_last_time (last_time),
  INDEX idx_flagged (flagged)
) ENGINE=InnoDB;

-- Scan summary
CREATE TABLE IF NOT EXISTS scan_summary (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  source VARCHAR(32),
  scan_paths TEXT,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NOT NULL,
  candidates INT NOT NULL,
  files_processed INT NOT NULL,
  bytes_processed BIGINT NOT NULL,
  flagged_new_count INT NOT NULL,
  flagged_total_after INT NOT NULL,
  missing_count INT NOT NULL,
  changed_count INT NOT NULL,
  reverified_count INT NOT NULL,
  av_found_count INT NOT NULL,
  av_quarantined_count INT NOT NULL,
  note TEXT,
  
  KEY idx_source (source, finished_at)
) ENGINE=InnoDB;

-- ClamAV events
CREATE TABLE IF NOT EXISTS av_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  detected_at DATETIME NOT NULL,
  source VARCHAR(32),
  path TEXT NOT NULL,
  signature VARCHAR(255) NOT NULL,
  engine VARCHAR(32) NOT NULL,
  action VARCHAR(32) NOT NULL,
  quarantine_path TEXT NULL,
  extra JSON NULL,
  
  UNIQUE KEY uniq_event (detected_at, signature(120), engine, path(255)),
  INDEX idx_detected (detected_at),
  INDEX idx_source (source)
) ENGINE=InnoDB;

-- ClamAV whitelist
CREATE TABLE IF NOT EXISTS av_whitelist (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  signature VARCHAR(255) NOT NULL,
  pattern TEXT NULL,
  reason TEXT NULL,
  
  UNIQUE KEY uniq_sig (signature(120))
) ENGINE=InnoDB;

-- Run summaries
CREATE TABLE IF NOT EXISTS run_summaries (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  source VARCHAR(32) NULL,
  cmd VARCHAR(32) NOT NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NOT NULL,
  candidates INT NOT NULL DEFAULT 0,
  files_processed INT NOT NULL DEFAULT 0,
  bytes_processed BIGINT NOT NULL DEFAULT 0,
  flagged_new INT NOT NULL DEFAULT 0,
  changed_count INT NOT NULL DEFAULT 0,
  reverified_count INT NOT NULL DEFAULT 0,
  scan_paths TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  KEY idx_src_time (source, started_at),
  KEY idx_cmd_time (cmd, started_at)
) ENGINE=InnoDB;

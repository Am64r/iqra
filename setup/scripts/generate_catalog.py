#!/usr/bin/env python3
"""
Generate catalog.json from a local folder of MP3 files.

Usage:
    python generate_catalog.py /path/to/quran/folder catalog.json

Then upload catalog.json to your R2 bucket root.
"""

import os
import sys
import json
from datetime import datetime

# Surah names lookup
SURAH_NAMES = {
    1: "Al-Fatihah", 2: "Al-Baqarah", 3: "Ali 'Imran", 4: "An-Nisa", 5: "Al-Ma'idah",
    6: "Al-An'am", 7: "Al-A'raf", 8: "Al-Anfal", 9: "At-Tawbah", 10: "Yunus",
    11: "Hud", 12: "Yusuf", 13: "Ar-Ra'd", 14: "Ibrahim", 15: "Al-Hijr",
    16: "An-Nahl", 17: "Al-Isra", 18: "Al-Kahf", 19: "Maryam", 20: "Ta-Ha",
    21: "Al-Anbiya", 22: "Al-Hajj", 23: "Al-Mu'minun", 24: "An-Nur", 25: "Al-Furqan",
    26: "Ash-Shu'ara", 27: "An-Naml", 28: "Al-Qasas", 29: "Al-Ankabut", 30: "Ar-Rum",
    31: "Luqman", 32: "As-Sajdah", 33: "Al-Ahzab", 34: "Saba", 35: "Fatir",
    36: "Ya-Sin", 37: "As-Saffat", 38: "Sad", 39: "Az-Zumar", 40: "Ghafir",
    41: "Fussilat", 42: "Ash-Shura", 43: "Az-Zukhruf", 44: "Ad-Dukhan", 45: "Al-Jathiyah",
    46: "Al-Ahqaf", 47: "Muhammad", 48: "Al-Fath", 49: "Al-Hujurat", 50: "Qaf",
    51: "Adh-Dhariyat", 52: "At-Tur", 53: "An-Najm", 54: "Al-Qamar", 55: "Ar-Rahman",
    56: "Al-Waqi'ah", 57: "Al-Hadid", 58: "Al-Mujadilah", 59: "Al-Hashr", 60: "Al-Mumtahanah",
    61: "As-Saff", 62: "Al-Jumu'ah", 63: "Al-Munafiqun", 64: "At-Taghabun", 65: "At-Talaq",
    66: "At-Tahrim", 67: "Al-Mulk", 68: "Al-Qalam", 69: "Al-Haqqah", 70: "Al-Ma'arij",
    71: "Nuh", 72: "Al-Jinn", 73: "Al-Muzzammil", 74: "Al-Muddaththir", 75: "Al-Qiyamah",
    76: "Al-Insan", 77: "Al-Mursalat", 78: "An-Naba", 79: "An-Nazi'at", 80: "'Abasa",
    81: "At-Takwir", 82: "Al-Infitar", 83: "Al-Mutaffifin", 84: "Al-Inshiqaq", 85: "Al-Buruj",
    86: "At-Tariq", 87: "Al-A'la", 88: "Al-Ghashiyah", 89: "Al-Fajr", 90: "Al-Balad",
    91: "Ash-Shams", 92: "Al-Layl", 93: "Ad-Duha", 94: "Ash-Sharh", 95: "At-Tin",
    96: "Al-'Alaq", 97: "Al-Qadr", 98: "Al-Bayyinah", 99: "Az-Zalzalah", 100: "Al-'Adiyat",
    101: "Al-Qari'ah", 102: "At-Takathur", 103: "Al-'Asr", 104: "Al-Humazah", 105: "Al-Fil",
    106: "Quraysh", 107: "Al-Ma'un", 108: "Al-Kawthar", 109: "Al-Kafirun", 110: "An-Nasr",
    111: "Al-Masad", 112: "Al-Ikhlas", 113: "Al-Falaq", 114: "An-Nas"
}


def extract_surah_number(filename):
    """Extract surah number from filename like '001-al-fatihah.mp3'."""
    import re
    match = re.match(r'^(\d{1,3})', filename)
    if match:
        num = int(match.group(1))
        if 1 <= num <= 114:
            return num
    return None


def slug_to_name(slug):
    """Convert 'yasser-ad-dossari' to 'Yasser Ad-Dossari'."""
    return ' '.join(word.capitalize() for word in slug.split('-'))


def get_audio_duration(filepath):
    """Get duration in seconds. Requires mutagen."""
    try:
        from mutagen.mp3 import MP3
        audio = MP3(filepath)
        return int(audio.info.length)
    except:
        return None


def main():
    if len(sys.argv) < 3:
        print("Usage: python generate_catalog.py <quran_folder> <output.json>")
        print("")
        print("Example:")
        print("  python generate_catalog.py ./quran catalog.json")
        print("")
        print("Expected folder structure:")
        print("  quran/")
        print("  └── yasser-ad-dossari/")
        print("      ├── 001-al-fatihah.mp3")
        print("      └── ...")
        sys.exit(1)
    
    quran_folder = sys.argv[1]
    output_file = sys.argv[2]
    
    if not os.path.isdir(quran_folder):
        print(f"Error: '{quran_folder}' is not a directory")
        sys.exit(1)
    
    catalog = {
        "version": 1,
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "reciters": [],
        "tracks": []
    }
    
    reciters_seen = {}
    
    # Walk through reciter folders
    for reciter_slug in sorted(os.listdir(quran_folder)):
        reciter_path = os.path.join(quran_folder, reciter_slug)
        
        if not os.path.isdir(reciter_path):
            continue
        
        if reciter_slug.startswith('.'):
            continue
        
        reciter_name = slug_to_name(reciter_slug)
        print(f"Processing reciter: {reciter_name}")
        
        # Add reciter
        if reciter_slug not in reciters_seen:
            catalog["reciters"].append({
                "slug": reciter_slug,
                "name": reciter_name
            })
            reciters_seen[reciter_slug] = reciter_name
        
        # Process MP3 files
        for filename in sorted(os.listdir(reciter_path)):
            if not filename.lower().endswith('.mp3'):
                continue
            
            filepath = os.path.join(reciter_path, filename)
            surah_num = extract_surah_number(filename)
            
            # Get title
            if surah_num and surah_num in SURAH_NAMES:
                title = SURAH_NAMES[surah_num]
            else:
                # Use filename as title
                title = os.path.splitext(filename)[0].replace('-', ' ').replace('_', ' ').title()
            
            # Build R2 path (relative to bucket root)
            r2_path = f"quran/{reciter_slug}/{filename}"
            
            # Get duration (optional)
            duration = get_audio_duration(filepath)
            
            track = {
                "title": title,
                "surah_number": surah_num,
                "reciter": reciter_slug,
                "r2_path": r2_path
            }
            
            if duration:
                track["duration_seconds"] = duration
            
            catalog["tracks"].append(track)
            print(f"  {surah_num or '?':3}. {title}")
    
    # Sort tracks by surah number
    catalog["tracks"].sort(key=lambda t: (t.get("surah_number") or 999, t["reciter"]))
    
    # Write output
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
    
    print(f"\n✓ Generated {output_file}")
    print(f"  - {len(catalog['reciters'])} reciters")
    print(f"  - {len(catalog['tracks'])} tracks")
    print(f"\nNext step: Upload {output_file} to your R2 bucket root")
    print(f"  wrangler r2 object put iqra-audio/catalog.json --file {output_file}")


if __name__ == '__main__':
    main()

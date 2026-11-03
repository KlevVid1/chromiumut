#!/usr/bin/python3
'''
 Copyright (C) 2022  UBPorts

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 3.

 udeb is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
'''
import os
import sys
import subprocess


#### Functions
def get_lcd_density() -> int:
  lcd_density = None
  process = None
  try:
    process = subprocess.Popen(
        ["getprop", "ro.sf.lcd_density"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
        universal_newlines=True
    )
    line = process.stdout.readline().strip()
    if line.isdigit():
      lcd_density = int(line)
    else:
      lcd_density = 0

  except Exception:
    return 0
  finally:
    if process and process.poll() is None:
        process.terminate()
        try:
          process.wait(timeout=2)
        except subprocess.TimeoutExpired:
          process.kill()
  
  return lcd_density or 0

def scalingdevidor(grid_px: float) -> int: 
  if grid_px >= 21:
    return 8
  elif grid_px <= 16:
    return 12
  else:
    return 10


def main():
  try:
    grid_px_str = os.environ.get("GRID_UNIT_PX", "").strip()
    grid_px = float(grid_px_str) if grid_px_str else 18.0
  except ValueError:
    grid_px = 18.0

  lcd_density = get_lcd_density()
  if lcd_density == 0:
    scaling = round(1.05 * grid_px / scalingdevidor(grid_px), 2)
  else:
    scaling = round(float(lcd_density) / 173.0, 2)

  # Fallback check
  if scaling <= 0:
    scaling = 2.0

  print(scaling)

if __name__ == "__main__":
  main()

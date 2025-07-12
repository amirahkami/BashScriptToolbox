# This script identifies and prints duplicate files based on their SHA-1 hash values.
# - The `find . -type f -exec shasum {} +` command generates the SHA-1 checksums for all files in the current directory and its subdirectories.
# - The `sort` command sorts the checksums alphabetically.
# - The `awk 'seen[$1]++'` command filters out files with unique checksums, leaving only duplicates.
# - The `cut -d' ' -f3-` removes the checksum value, leaving only the file names.
# - The `while read file; do` loop iterates through each file name and checks how many times it appears in the list of files with matching checksums.
# - The `count=$(grep -c "^$file$" <<< "$(find . -type f -exec shasum {} + | sort | cut -d' ' -f3-)")` counts the number of occurrences of the current file.
# - The script then prints a separator line and repeats the file name `count` times, indicating the number of duplicates.

find . -type f -exec shasum {} + | sort | awk 'seen[$1]++' | cut -d' ' -f3- | while read file; do
  count=$(grep -c "^$file$" <<< "$(find . -type f -exec shasum {} + | sort | cut -d' ' -f3-)")
  echo "+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
  for i in $(seq 1 $count); do
    echo "$file"
  done
done
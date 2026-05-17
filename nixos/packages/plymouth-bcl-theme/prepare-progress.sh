for file in frame_*_delay-0.04s.png; do
  # Extract the numeric part (e.g., 000, 001, 123)
  num=$(echo "$file" | sed 's/frame_\([0-9]*\)_delay-.*/\1/')
  # Convert to integer to remove leading zeros
  num=$((10#$num))
  # Rename to progress-{number}.png
  mv "$file" "progress-$num.png"
done
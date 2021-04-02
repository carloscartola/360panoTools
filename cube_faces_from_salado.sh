#!/usr/bin/env bash
#
# Script to convert multi resolution tiles from Salado Converter (deep zoom
# format) to cube faces with the bigger resolution found, then generate the
# krpano multi resolution tiles

# CONFIGURATION
if [ -z "$2" ]; then
  echo -e "\n\tUsage: $0 <deep zoom directory> <output prefix>\n"
  exit
fi
if [ -z "$(which montage 2> /dev/null)" ]; then
  echo -e "\n\t'montage' not found. Imagemagick must be installed.\n"
  exit
fi
dz_dir="$1"
output_prefix="$2"
dz_name="$(echo "$dz_dir" | sed -e 's/dz_//')"
higher_resolution="$(\ls "$dz_dir/${dz_name}_f" | sort -n | tail -1)"
width="$(\ls "$dz_dir/${dz_name}_f/$higher_resolution" | cut -d_ -f1 | \
  sort -n | tail -1)"
high="$(\ls "$dz_dir/${dz_name}_f/$higher_resolution" | cut -d_ -f2 | \
  cut -d. -f1 | sort -n | tail -1)"

# Check acquired data
echo Dir: $dz_dir
echo Name: $dz_name
echo Higher resolution dir: $higher_resolution
echo Tiles: width = $width, high = $high

# FUNCTIONS
_make_big_tile() {
  # Receives:
  #   1. dz_dir
  #   2. Tile dir code (f, b, u, d, l, r)
  #   3. tiles dir
  #   4. File name prefix
  #   5. Number of tiles in width
  #   6. Number of tiles in high
  # Returns: Final image name: prefix_$tile_dir_code.jpg
  if [ -z "$4" ]; then
    echo -e "\n\tFunction ${FUNCNAME[0]} requires:"
    echo -n -e "\t<dz_dir> <tile dir code> <tiles_dir> <file name prefix> "
    echo -e "<# width> <# high>\n"
    exit
  fi
  # Local variables start with "l_"
  l_dz_dir="$1"
  l_tile_dir_code="$2"
  l_tiles_dir="$3"
  l_prefix="$4"
  l_width="$5"
  l_high="$6"
  for l_line in $(seq 0 $l_high); do
    name_p1="${l_dz_dir}_${l_tile_dir_code}"
    name_p2="/${l_tiles_dir}/{0..${l_width}}_${l_line}.jpg"
    eval montage "${name_p1}${name_p2}" -tile $((l_width+1))x1 -geometry +0+0 \
      ${l_prefix}_${l_line}.jpg
  done
  eval montage ${l_prefix}_{0..${l_width}}.jpg -tile 1x$((l_high+1)) -geometry +0+0 \
    ${l_prefix}_${l_tile_dir_code}.jpg
}

_calculate_num_levels() {
  # Receives:
  #   1. Top level (highest resolution) side size
  #   2. Tile size
  if [ -z "$2" ]; then
    echo -e "\n\tFunction ${FUNCNAME[0]} requires:"
    echo -e "\t<highest resolution cube size> <tile size>"
    exit
  fi
  # Local variables start with "l_"
  l_side="$1"
  l_tile="$2"
  # Will double smallest until it passes biggest side
  l_levels=1
  l_test_side=$l_tile
  while [ $l_test_side -lt $l_side ]; do
    l_test_side=$((l_test_side * 2))
    l_levels=$((l_levels + 1))
  done
  echo $l_levels
}

_calculate_level_side_size() {
  # Receives:
  #   1. Current level number
  #   2. Top level (highest resolution) side size
  #   3. Tile size
  if [ -z "$3" ]; then
    echo -e "\n\tFunction ${FUNCNAME[0]} requires:"
    echo -e "\t<current level num> <highest resolution cube size> <tile size>"
    exit
  fi
  # Local variables start with "l_"
  l_level="$1"
  l_biggest_side="$2"
  l_tile_size="$3"
  #
  if [ $l_level = 1 ]; then
    echo $l_tile_size
  else
    l_size=$(( l_tile_size * (2 ** (l_level - 1)) ))
    if [ $l_size -gt $l_biggest_side ]; then
      echo $l_biggest_side
    else
      echo $l_size
    fi
  fi
}

_make_multi_resolution() {
  # Receives:
  #   1. ${output_prefix}
  #   2. Tile size
  if [ -z "$2" ]; then
    echo -e "\n\tFunction ${FUNCNAME[0]} requires:"
    echo -e "\t<file name prefix> <tile size>"
    exit
  fi
  # Local variables start with "l_"
  l_prefix="$1"
  l_tile="$2"
  l_crop="${l_tile}x${l_tile}"
  l_top_cube_size="$(identify "${output_prefix}"_f.jpg | cut -d\  -f3 | \
    cut -dx -f1)"
  l_levels=$(_calculate_num_levels $l_top_cube_size $l_tile)
  # index.tiles/mres_%s/l1/%v/l1_%s_%v_%h.jpg
  # Generate levels part of image.xml
  for l_level in $(seq 1 $l_levels); do
    if [ $l_level = $l_levels ]; then
      l_aux_size=$l_top_cube_size
    else
      l_aux_size=$((512*(2**(l_level - 1))))
    fi
    echo -e "\t\t<level tiledimagewidth=\"$l_aux_size\"" \
      "tiledimageheight=\"$l_aux_size\">" >> image.xml
		echo -e "\t\t\t<cube" \
      "url=\"index.tiles/mres_%s/l$l_level/%v/l${l_level}_%s_%v_%h.jpg\"" \
      "/>\n\t\t</level>" >> image.xml
  done
  mkdir -p "${l_prefix}.tiles"
  #----------------
  # Cube faces loop
  for l_side in l f r b u d; do
    echo -e "\tGenerating multires for side $l_side..."
    mkdir -p "${l_prefix}.tiles/mres_$l_side"
    #-------------------------------
    # Levels loop for each cube face
    for l_level in $(seq 1 $l_levels); do
      echo -e "\tGenerating level $l_level..."
      l_level_size=$(_calculate_level_side_size $l_level \
        $l_top_cube_size $l_tile)
      # last level might have different crop size
      if [ "$l_level" == "$l_levels" ]; then
        l_base_image="${l_prefix}_${l_side}.jpg"
        if [ $((l_level_size % l_tile)) == 0 ]; then
          l_lines=$((l_level_size / l_tile))
          l_last_crop=$l_tile
        else
          l_lines=$(((l_level_size / l_tile)+1))
          l_last_crop=$((l_level_size % l_tile))
        fi
      else
        # create image with the level cube size
        l_base_image="${l_prefix}.$l_side.$l_level.jpg"
        convert -resize $l_level_size ${output_prefix}_$l_side.jpg \
          "$l_base_image"
        l_lines=$((l_level_size / l_tile))
      fi
      for l_col in $(seq 1 $l_lines); do
        echo -n "Column $l_col Line "
        # create the tiles
        l_dir="${l_prefix}.tiles/mres_$l_side/l$l_level/$l_col"
        mkdir -p "$l_dir"
        for l_line in $(seq 1 $l_lines); do # l_lines again. Its a square.
          echo -n "$l_line "
          if [ "$l_level" = "$l_levels" ]; then
            # Last line and col of highest level may have different crop size
            if [ $l_col = $l_lines ]; then
              l_aux_col_tile=$l_last_crop
            else
              l_aux_col_tile=$l_tile
            fi
            if [ $l_line = $l_lines ]; then
              l_aux_line_tile=$l_last_crop
            else
              l_aux_line_tile=$l_tile
            fi
            l_aux_crop="${l_aux_line_tile}x${l_aux_col_tile}"
          else
            l_aux_crop=$l_crop
          fi
          l_geo1=$(((l_line-1)*l_tile))
          l_geo2=$(((l_col-1)*l_tile))
          convert "$l_base_image" \
            -crop $l_aux_crop+$l_geo1+$l_geo2 +repage \
            "$l_dir"/l${l_level}_${l_side}_${l_col}_${l_line}.jpg
        done
        echo
      done
    done
  done
}

# MAIN
for side in f b u d l r; do
  echo "Generating side $side..."
  _make_big_tile $dz_dir/$dz_name $side $higher_resolution \
    $output_prefix $width $high
  echo "Generating side $side preview..."
  convert -resize 256 ${output_prefix}_${side}.jpg \
    ${output_prefix}_preview_${side}.jpg
done

echo "Generating final preview..."
montage ${output_prefix}_preview_{l,f,r,b,u,d}.jpg -tile 1x6 -geometry +0+0 \
  ${output_prefix}_preview.jpg

echo "Generating multi-resolution for deep zoom by sides: "
echo -e "\tleft (l), front (f), right (r), back (b), up (u) and down (d)..."
# Initiate image.xml
echo -e '<krpano>
	<view hlookat="350" vlookat="90" maxpixelzoom="1.0" fovmax="150" fov="150" fisheye="1.0"
		stereographic="true" fisheyefovlink="3.0" />
	<autorotate enabled="true" waittime="15" accel="1.0" speed="15.0" horizon="0.0" tofov="100" />

	<preview url="index.tiles/preview.jpg" />
	<image type="CUBE" multires="true" tilesize="512">' > image.xml
_make_multi_resolution "${output_prefix}" 512
# Finish image.xml
echo -e '	</image>
</krpano>' >> image.xml

mv ${output_prefix}_preview.jpg ${output_prefix}.tiles/preview.jpg

echo "Cleaning temp files..."
rm -f ${output_prefix}_[0-9]*.jpg ${output_prefix}_preview_*.jpg ${output_prefix}.?.?.jpg

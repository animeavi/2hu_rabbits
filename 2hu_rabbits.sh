#!/bin/bash

# Based on https://git.fai.su/dendy/fedibooru-bot
# Needs curl, jq, wget

# https://github.com/animeavi/fedi_ebooks/blob/master/auth_helper.rb

cd "${0%/*}"

get_conf(){
    str=$(grep "$1" config)
    echo ${str#$1=}
}

access_token=$(get_conf access_token)
instance=$(get_conf instance)
img_dir=$(get_conf img_dir)
post_text=$(get_conf post_text)
visibility=$(get_conf visibility) # public, unlisted, private

querybase="https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1&tags="

# URL encode this (ie copy from a danbooru search)
extra_param="+rating%3Ageneral"
declare -a Rabbits=( "reisen_udongein_inaba" "inaba_tewi" "ringo_%28touhou%29" "seiran_%28touhou%29" "reisen_%28touhou_bougetsushou%29" )
declare -a ImageIds=()

[ -d "$img_dir" ] || mkdir "$img_dir" || (echo "Error creating image folder" && exit 1)
for rabbit in ${Rabbits[@]}; do
   query="$querybase$rabbit$extra_param"

   # Find maximum number of pages possible first
   curl "$query" > "$img_dir/pages.json"

   if ! jq -r type "$img_dir/pages.json" >/dev/null 2>&1; then
     echo "Got invalid JSON as a response!"
     exit 1
   fi

   count=$(jq -r '."@attributes".count' "$img_dir/pages.json")
   rm -rf "$img_dir/pages.json"
   pages=$((($count/100)-1)) # 0 index

   # This is the limit of the API
   if [ "$pages" -gt 200 ]; then
     pages=200
   fi

   # Grab a random page of results
   random_page=$(shuf -i 0-"$pages" -n 1)
   query="$query&pid=$random_page"
   echo $query

   n=1
   while [ $n -le 10 ]
   do
     curl "$query" > "$img_dir/results.json"
     result_count=$(jq ".post | length" "$img_dir/results.json")
     result_count=$(($result_count-1)) # 0 index

     # Grab a random item from the results we got
     random_result=$(shuf -i 0-"$result_count" -n 1)
     imageurl=$(jq -r ".post[$random_result].file_url" "$img_dir/results.json")
     rm -rf "$img_dir/results.json"

     if [[ $imageurl == *jpg ]] || [[ $imageurl == *jpeg ]] || [[ $imageurl == *png ]] || [[ $imageurl == *gif ]]; then
        wget "$imageurl" -P "$img_dir" 2> /dev/null || (echo "Could not download image" && exit 1)

        image_json=$( \
            curl -X POST "https://$instance/api/v1/media" \
            -H "Authorization: Bearer $access_token" \
            -F "file=@$img_dir/$(basename "$imageurl")" \
            -F "description=$(basename "$imageurl")" 2> /dev/null \
        )

        id=$(jq -r ".id" <<< "$image_json")
        ImageIds+=($id)
        break
     fi

     (( n++ ))
     sleep 1
   done
done

ids_json=$(jq --compact-output --null-input '$ARGS.positional' --args "${ImageIds[@]}")

curl -X POST -d '{"status":"'"$post_text"'", "visibility":"'"$visibility"'", "media_ids":'"$ids_json"'}' \
 -H "Authorization: Bearer $access_token" \
 -H "Content-Type: application/json" \
 "https://$instance/api/v1/statuses"

rm -rf $img_dir/*.*

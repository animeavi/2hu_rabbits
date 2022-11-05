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

querybase="https://danbooru.donmai.us/posts/random.json?tags="

# URL encode this (ie copy from a danbooru search)
extra_param="+rating%3asafe"
declare -a Rabbits=( "reisen_udongein_inaba" "inaba_tewi" "ringo_%28touhou%29" "seiran_%28touhou%29" "reisen_%28touhou_bougetsushou%29" )
declare -a ImageIds=()

[ -d "$img_dir" ] || mkdir "$img_dir" || (echo "Error creating image folder" && exit)
for rabbit in ${Rabbits[@]}; do
   query="$querybase$rabbit$extra_param"

   n=1
   while [ $n -le 10 ]
   do
     json=$(curl "$query" 2> /dev/null)
     imageurl=$(jq -r ".file_url" <<< "$json")

     if [[ $imageurl == *jpg ]] || [[ $imageurl == *jpeg ]] || [[ $imageurl == *png ]] || [[ $imageurl == *gif ]]; then
        wget "$imageurl" -P "$img_dir" 2> /dev/null || (echo "Could not download image" && exit)

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

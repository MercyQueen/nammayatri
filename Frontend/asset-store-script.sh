#!/bin/bash

branch_name=$1

files_to_be_added=();

add_file_for_commit() { #dir , sub_dir, asset_type, asset_name, source_path
    local dir="$1"
    local sub_dir="$2"
    local asset_type="$3"
    local asset_name="$4"
    local updated_path="beckn/$dir/$sub_dir/$asset_type/$asset_name"
    files_to_be_added+=("../../$source_path:$updated_path")

    echo "Inside add_file_for_commit" $source_path "->" $updated_path
}

# Function to create a Pull Request
create_pull_request() {
    local target_repo_name="asset-store"
    echo "target_repo_name"
    if [ -z "$branch_name" ]; then
        echo "Error: Branch name not provided"
        return 1
    fi

    git checkout "$branch_name"

    # Fetch the changes
    git fetch origin "$branch_name"
    declare -a staged_files_array
    for file in "${ALL_CHANGED_FILES[@]}"; do
        staged_files_array+=("$file")
        echo "$file was changed"
    done

    echo "$target_repo_name"

    cd "$target_repo_name" || { echo "Error: Directory $target_repo_name does not exist after cloning"; return 1; }
    git checkout main
    git pull origin --rebase main || { echo "Error: Failed to pull latest changes"; return 1; }
    git branch -D "$branch_name" >/dev/null 2>&1 || true
    git checkout -b "$branch_name" || { echo "Error: Failed to create or checkout branch $branch_name"; return 1; }
    git pull origin --rebase main || { echo "Error: Failed to pull latest changes"; return 1; }


    # Process staged files and copy them to appropriate locations
    local allowed_extensions=("png" "jpg" "xml" "json")
    local filestobeadded=()

    for file in "${staged_files_array[@]}"; do
        extension="${file##*.}"

        if [[ " ${allowed_extensions[@]} " =~ " $extension " ]]; then
            source_path="$file"
            IFS="/" read -ra src_path_components <<< "$source_path"

            length=${#src_path_components[@]}
            dir=${src_path_components[5]}
            dir_array=()
            final_dir=""
            sub_dir=${src_path_components[4]}

            asset_name=${src_path_components[length-1]}

            # Determine file type based on path_components[3]
            if [[ ${src_path_components[length-2]} == "drawable" ]]; then
                file_type="images"
            else
                file_type="lottie"
            fi
            asset_type=${file_type}

            if [[ ${sub_dir} == "main" && ${dir} == *"Common"* ]]; then
                substring="Common"
                result="${dir//$substring/}" 
                add_file_for_commit "$result" "$dir" "$asset_type" "$asset_name" "$source_path"
            else 
                if echo "$dir" | grep -q "jatriSaathi"; then
                    final_dir="jatrisaathi"
                elif echo "$dir" | grep -q "nammaYatri"; then
                    final_dir="nammayatri"
                elif echo "$dir" | grep -q "yatri"; then
                    final_dir="yatri"
                elif echo "$dir" | grep -q "manayatri"; then
                    final_dir="manayatri"
                else 
                    final_dir=""
                fi
                if [[ "$final_dir" == "" ]]; then
                    if [[ ${sub_directory} == "main" ]]; then 
                        add_file_for_commit "common" "common" "$asset_type" "$asset_name" "$source_path"
                    elif [[ "$dir" == "common" ]]; then
                        add_file_for_commit "common" "$sub_dir" "$asset_type" "$asset_name" "$source_path"    
                    else
                        add_file_for_commit "$final_dir" "$sub_dir" "$asset_type" "$asset_name" "$source_path"
                    fi
                fi
            fi
        fi
    done 
    for item in "${files_to_be_added[@]}"; do
        source_path="${item%:*}"
        updated_path="${item#*:}"
        cp "$source_path" "$updated_path"
    done

    git add .
    git commit -m "[GITHUB-ACTION]Added new asset from NammaYatri/NammaYatri branch : $branch_name"
    git push --set-upstream origin "$branch_name"
    git push #origin "$branch_name" || { echo "Error: Failed to push changes to branch $branch_name"; return 1; }
    pull_request_url="${target_repo}/compare/main...${branch_name}"
    echo "Pull request URL: $pull_request_url"
    curl -X POST -H "Authorization: token $PAT_TOKEN" \
        https://api.github.com/repos/MercyQueen/asset-store/dispatches \
        -d '{"event_type": "trigger_workflow",  "client_payload": {"branch": "'$branch_name'" , "ref" : "main"}}'

    cd ..
    rm -rf "$target_repo_name" 
}

# Loop through target repositories and create pull requests
create_pull_request

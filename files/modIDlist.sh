#!/bin/sh
# filepath: gummy_foods

# Initialize variables
HERE="$(pwd)"
MODLOADER=""
MCMAJOR=""
MCMINOR=""

# Check if mods directory exists
if [ ! -d "$HERE/mods" ]; then
    echo "\nPROBLEM - NO MODS FOLDER FOUND\n"
    echo "PLACE THIS modId SCANNER IN THE MAIN MODPACK OR SERVER FOLDER"
    echo "DO NOT PUT INSIDE THE MODS FOLDER ITSELF\n"
    exit 1
fi

echo "\nMAKING LIST OF FILES - PLEASE WAIT...\n"

# Get list of jar files
cd mods || exit
MODS_LIST=$(find . -maxdepth 1 -name "*.jar" -type f)
MODS_COUNT=$(echo "$MODS_LIST" | wc -l)

# Detect modloader type from minecraftinstance.json if it exists
if [ -f "../minecraftinstance.json" ]; then
    echo "FOUND A CURSEFORGE minecraftinstance.json - USING IT TO SET PROFILE TYPE!\n"
    
    # Use jq if available, otherwise fall back to grep
    if command -v jq >/dev/null 2>&1; then
        LOADER_NAME=$(jq -r '.baseModLoader.name' ../minecraftinstance.json)
        MC_VERSION=$(jq -r '.baseModLoader.minecraftVersion' ../minecraftinstance.json)
    else
        LOADER_NAME=$(grep -o '"name":"[^"]*' ../minecraftinstance.json | cut -d'"' -f4)
        MC_VERSION=$(grep -o '"minecraftVersion":"[^"]*' ../minecraftinstance.json | cut -d'"' -f4)
    fi

    case "$LOADER_NAME" in
        *FORGE*) MODLOADER="FORGE" ;;
        *NEOFORGE*) MODLOADER="NEOFORGE" ;;
        *FABRIC*) MODLOADER="FABRIC" ;;
    esac

    # Parse Minecraft version
    MCMAJOR=$(echo "$MC_VERSION" | cut -d'.' -f2)
    MCMINOR=$(echo "$MC_VERSION" | cut -d'.' -f3)
else
    # Ask user for modloader type if json not found
    while true; do
        echo "\nPLEASE SELECT WHICH MODLOADER TYPE YOUR PROFILE LAUNCHES WITH!\n"
        echo "[1] - FORGE"
        echo "[2] - NEOFORGE" 
        echo "[3] - FABRIC"
        echo "[Q] - Quit\n"
        printf "Enter choice (1-3, Q): "
        read -r choice
        
        case "$choice" in
            1) MODLOADER="FORGE"; break ;;
            2) MODLOADER="NEOFORGE"; break ;;
            3) MODLOADER="FABRIC"; break ;;
            [Qq]) exit 0 ;;
            *) echo "Invalid choice, try again" ;;
        esac
    done

    # Get Minecraft version from user
    while true; do
        echo "\nENTER THE MINECRAFT VERSION"
        echo "example: 1.12.2"
        echo "example: 1.20.1\n"
        printf "ENTRY: "
        read -r MC_VERSION
        
        if echo "$MC_VERSION" | grep -q "^1\."; then
            MCMAJOR=$(echo "$MC_VERSION" | cut -d'.' -f2)
            MCMINOR=$(echo "$MC_VERSION" | cut -d'.' -f3)
            [ -z "$MCMINOR" ] && MCMINOR=0
            break
        else
            echo "\nInvalid Minecraft version format, try again!"
        fi
    done
fi

# Function to scan mod file
scan_mod_file() {
    local jar_file="$1"
    local mod_type=""
    local mod_id=""
    local dependencies=""

    # Check for Forge/Fabric identifiers
    if unzip -l "$jar_file" | grep -q "META-INF/mods.toml"; then
        mod_type="FORGE"
    elif unzip -l "$jar_file" | grep -q "fabric.mod.json"; then
        mod_type="FABRIC"
    elif unzip -l "$jar_file" | grep -q "mcmod.info"; then
        mod_type="FORGE_OLD"
    fi

    # Extract mod ID based on type
    case "$mod_type" in
        "FORGE")
            mod_id=$(unzip -p "$jar_file" "META-INF/mods.toml" | grep -m1 "modId.*=" | cut -d'"' -f2)
            ;;
        "FABRIC")
            if command -v jq >/dev/null 2>&1; then
                mod_id=$(unzip -p "$jar_file" "fabric.mod.json" | jq -r .id)
                dependencies=$(unzip -p "$jar_file" "fabric.mod.json" | jq -r '.depends | keys[]' 2>/dev/null)
            else
                mod_id=$(unzip -p "$jar_file" "fabric.mod.json" | grep '"id"' | cut -d'"' -f4)
            fi
            ;;
        "FORGE_OLD")
            mod_id=$(unzip -p "$jar_file" "mcmod.info" | grep -m1 '"modid"' | cut -d'"' -f4)
            ;;
    esac

    echo "$mod_type:$mod_id:$dependencies"
}

# Process each mod
echo "SCANNING MOD FILES - PLEASE WAIT...\n"

# Create output file
REPORT_FILE="../modslist.txt"
i=1
while [ -f "$REPORT_FILE" ]; do
    REPORT_FILE="../modslist$i.txt"
    i=$((i + 1))
done

{
    echo "----------------------------------------"
    echo "  $MODLOADER - 1.$MCMAJOR.$MCMINOR"
    echo "----------------------------------------"
    echo "     modID   -   file name"
    echo "----------------------------------------"

    for jar_file in $MODS_LIST; do
        result=$(scan_mod_file "$jar_file")
        mod_type=$(echo "$result" | cut -d':' -f1)
        mod_id=$(echo "$result" | cut -d':' -f2)
        dependencies=$(echo "$result" | cut -d':' -f3-)

        # Format and write to report
        printf "  %-20s - %s\n" "$mod_id" "$(basename "$jar_file")"
        
        if [ -n "$dependencies" ]; then
            echo "$dependencies" | while read -r dep; do
                [ -n "$dep" ] && printf "  %-20s   - %s\n" "" "$dep"
            done
        fi
    done
    
    echo "----------------------------------------"
} > "$REPORT_FILE"

# Display report
cat "$REPORT_FILE"

exit 0

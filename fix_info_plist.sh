#!/bin/bash

# 读取原始文件
input_file="/Users/honghaoliu/OpenClaw/Projects/AssetScanner/AssetScanner.xcodeproj/project.pbxproj"
output_file="/Users/honghaoliu/OpenClaw/Projects/AssetScanner/AssetScanner.xcodeproj/project.pbxproj.fixed"

# 清理现有的 CFBundleLocalizations 行
sed '/CFBundleLocalizations/d' "$input_file" > "$output_file"

# 在正确的位置插入 CFBundleLocalizations
awk '
BEGIN { in_build_settings = 0; inserted = 0 }
/^[[:space:]]*buildSettings[[:space:]]*=[[:space:]]*{$/ { 
    in_build_settings = 1; 
    print;
    next;
}
in_build_settings && /^[[:space:]]*INFOPLIST_KEY_CFBundleDisplayName[[:space:]]*=/ {
    print $0;
    print "				INFOPLIST_KEY_CFBundleLocalizations = ( \"zh-Hans\", \"en\" );";
    inserted = 1;
    next;
}
/^[[:space:]]*};$/ && in_build_settings {
    in_build_settings = 0;
    inserted = 0;
    print;
    next;
}
{ print }
' "$output_file" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"

# 备份原文件并替换
mv "$input_file" "$input_file.bak2"
mv "$output_file" "$input_file"

echo "Fixed project.pbxproj"
# AutomaticDeployJavaMavenProject
Linux Bash Shell Automatic Deploy Java Maven Project( Remote deploy supported)

Please modify those setting in shell script file, and take attention to deploy() function if you need a maven dependence(like project_clone_depends_1).

project_clone_depends_1="ssh://git@xxx/xxx1.git"

project_clone="ssh://git@xxx/xxx.git"

deploy_target_host_ip="xxx.xxx.xxx.xxx"

project_top_directory_to_target_host="/path/to/deploy"

Good luck, :)

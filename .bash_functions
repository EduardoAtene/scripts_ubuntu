function help() {
    display_help
}

function start() {
    base_branch="sprint3-multiportal-feature"
    new_branch=""
    
    # Parse arguments
    TEMP=`getopt --long -o "b:f:h" "$@"`
    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            -b )
                new_branch=$2
                shift 2
            ;;
            -f )
                base_branch=$2
                shift 2
            ;;
            -h )
                echo "Uso: start -b <nova_branch> [-f <branch_base>]"
                echo "  -b : Nome da nova branch"
                echo "  -f : Branch base (padrão: sprint3-multiportal-feature)"
                return 1
            ;;
            *)
                break
            ;;
        esac
    done;

    # Validar se o nome da branch foi fornecido
    if [[ -z "$new_branch" ]]; then
        echo "[ERROR] Nome da branch não especificado"
        return 1
    fi

    # Criar e mudar para a nova branch
    git checkout -b "$new_branch" "$base_branch"
    
    if [[ $? -eq 0 ]]; then
        echo "Branch '$new_branch' criada a partir de '$base_branch'"
    else
        echo "[ERROR] Não foi possível criar a branch"
        return 1
    fi
}

function generate_pr_body() {
    echo "Commits:"
    git log --pretty=format:" - %s" origin/${branch}..HEAD
}

function merge() {
    branch="sprint3-multiportal-feature"
    identifier="COR-XXXX"
    identifier_type="COR"
    desc=""
    error_message=""

    if [[ "$1" == "-h" ]]; then
        display_help
        return 1
    fi

    TEMP=`getopt --long -o "b:i:t:d:h" "$@"`
    eval set -- "$TEMP"

    while true ; do
        case "$1" in
            -b )
                branch=$2
                shift 2
            ;;
            -i )
                identifier=$2
                shift 2
            ;;
            -t )
                identifier_type=$2
                shift 2
            ;;
            -d )
                desc=$2
                shift 2  
            ;;
            -h )
                display_help
                return 1
            ;;
            *)
                break
            ;;
        esac
    done;

    # Validate identifier and type
    if [[ $identifier == "${identifier_type}-XXXX" ]]; then 
        error_message+="[ERROR] Nenhum número de ${identifier_type} informado\n"
    fi 

    if [[ $desc == "" ]]; then 
        error_message+="[ERROR] Nenhuma descrição informada\n"
    fi 

    if [[ -n $error_message ]]; then
        echo -e "$error_message"
        return 1
    fi

    echo "Executando: git push origin HEAD"
    git push origin HEAD
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Não foi possível fazer o push para a branch."
        return 1
    fi

    pr_body=$(generate_pr_body)

    echo "Executando: gh pr create --base ${branch} --title [${identifier_type}-${identifier}] ${desc} --body ${pr_body}"
    pr_url=$(gh pr create --base "${branch}" --title "[${identifier_type}-${identifier}] ${desc}" --body "${pr_body}")
    
    if [[ $? -eq 0 ]]; then
        echo "Pull Request criada com sucesso: ${pr_url}"
        
        pr_title="[${identifier_type}-${identifier}] ${desc}"
        
        # Use full path to the script
        webhook_response=$(go run ~/send_slack_message.go "${pr_url}" "${pr_title}")
        
        echo "$webhook_response"
    else
        echo "[ERROR] Não foi possível criar a Pull Request."
    fi
}


function up() {
    branch="sprint3-multiportal-feature"
    error_message=""

    if [[ "$1" == "-h" ]]; then
        display_help
        return 1
    fi

    TEMP=`getopt --long -o "b:h" "$@"`
    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            -b )
                branch=$2
                shift 2
            ;;
            -h )
                display_help
                return 1
            ;;
            *)
                break
            ;;
        esac
    done;

    echo "Executando: git push origin HEAD"
    git push origin HEAD
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Não foi possível fazer o push para a branch."
        return 1
    fi

    pr_number=$(gh pr list --base "${branch}" --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number')
    
    if [[ -z "$pr_number" ]]; then
        error_message+="[ERROR] Nenhuma PR existente encontrada para esta branch.\n"
    fi

    if [[ -n $error_message ]]; then
        echo -e "$error_message"
        return 1
    fi

    pr_body=$(generate_pr_body)

    echo "Executando: gh pr edit $pr_number --body $pr_body"
    gh pr edit "$pr_number" --body "$pr_body"
    
    if [[ $? -eq 0 ]]; then
        echo "Descrição da Pull Request atualizada com sucesso."
    else
        echo "[ERROR] Não foi possível atualizar a descrição da Pull Request."
    fi
}


function commit() {
    type="invalid"
    emoji=""
    msg=""

    TEMP=`getopt --long -o "t:m:h" "$@"`
    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            -t )
                type=$2
                shift 2
            ;;
            -m )
                msg=$2
                shift 2
            ;;
            *)
                break
            ;;
        esac
    done;

    if [[ ${type} == "feat" ]]; then
        emoji=✨
    elif [[ ${type} == "fix" ]]; then 
        emoji=🔧
    elif [[ ${type} == "bug" ]]; then 
        emoji=🪲
    elif [[ ${type} == "refactor" ]]; then
        emoji=🔃
    elif [[ ${type} == "build" ]]; then
        emoji=🛠
    elif [[ ${type} == "comment" ]]; then
        emoji=💡
    elif [[ ${type} == "delete" ]]; then
        emoji=❌
    elif [[ ${type} == "dependency" ]]; then
        emoji=📦
    elif [[ ${type} == "deploy" ]]; then
        emoji=🚀
    elif [[ ${type} == "docs" ]]; then
        emoji=📄
    elif [[ ${type} == "downgrade" ]]; then
        emoji=🔽
    elif [[ ${type} == "rename" ]]; then
        emoji=🔤
    elif [[ ${type} == "revert" ]]; then
        emoji=💥
    elif [[ ${type} == "review" ]]; then
        emoji=👌
    elif [[ ${type} == "security" ]]; then
        emoji=🔒
    elif [[ ${type} == "style" ]]; then
        emoji=💄
    elif [[ ${type} == "test" ]]; then 
        emoji=🧪
    elif [[ ${type} == "upgrade" ]]; then
        emoji=🔼
    elif [[ ${type} == "wip" ]]; then
        emoji=🚧
    fi

    if [[ ${type} == "invalid" ]]; then
        echo ""
        echo "[ERROR] Nenhum tipo de commit especificado"
    fi 

    if [[ ${msg} == "" ]]; then
        echo ""
        echo "[ERROR] Nenhuma mensagem de commit especificada"t Onfly!
    fi 

    if [[ ${type} != "invalid" ]] && [[ {$msg} != "" ]]; then
        user=$(git config user.name)
        command="git commit -m '${emoji} ${type^}: ${msg}'"
        echo "${command}"
        eval $command
    else  
        echo ""
        echo -e "-m \t para especificar a mensagem do commit"
        echo -e "-t \t para especificar o tipo de commit" 
        echo ""
        echo -e "Tipos de commit disponíveis: \n"
        
        echo -e "🪲 bug \t\t Para commitar uma correção de bug" 
        echo -e "🔨 build \t Para commitar uma alteração durante build da aplicação" 
        echo -e "💡 comment \t Para commitar um comentário de código"
        echo -e "❌ delete \t Para commitar uma remoção de arquivo"
        echo -e "🚀 deploy \t Para commitar uma alteração no deploy" 
        echo -e "📦 dependency \t Para commitar a instalação de um novo pacote"
        echo -e "📄 docs \t Para commitar uma alteração na documentação"
        echo -e "🔽 downgrade \t Para commitar um rollback de versão"
        echo -e "✨ feat \t Para commitar uma nova funcionalidade"
        echo -e "🔧 fix \t\t Para commitar um ajuste em uma nova funcionalidade"  
        echo -e "🔃 refactor \t Para commitar uma refatoração de código" 
        echo -e "🔤 rename \t Para commitar uma mudança de nome ou namespace"
        echo -e "💥 revert \t Para commitar um rollback de código" 
        echo -e "👌 review \t Para commitar um ajuste de Code Review" 
        echo -e "🔒 security \t Para commitar uma ajuste de segurança"
        echo -e "💄 style \t Para commitar uma alteração de estilização"
        echo -e "🧪 test \t Para commitar um teste automatizado"
        echo -e "🔼 upgrade \t Para commitar uma atualização de versão"
        echo -e "🚧 wip \t\t Para commitar uma mudança ainda em desenvolvimento/em andamento"
    fi
}

function sprint3() {
    branch_from="sprint3-multiportal-feature"
    branch_to="sprint3"
    desc="[Reverso PR] Merge ${branch_from} into ${branch_to}"

    echo "Iniciando o processo de criação da PR '-' ..."

    command="gh pr create --base ${branch_to} --head ${branch_from} --title '${desc}' --fill --web"
    
    eval $command

    if [[ $? -eq 0 ]]; then
        echo "Pull Request criada com sucesso e aberta no navegador."
    else
        echo "[ERROR] Não foi possível criar a Pull Request."
        return 1
    fi
}

function staging() {
    branch_from="sprint3-multiportal-feature"
    branch_to="staging"
    desc="[Reverso PR] Merge ${branch_from} into ${branch_to}"

    echo "Iniciando o processo de criação da PR '-' ..."

    command="gh pr create --base ${branch_to} --head ${branch_from} --title '${desc}' --fill --web"
    
    eval $command

    if [[ $? -eq 0 ]]; then
        echo "Pull Request criada com sucesso e aberta no navegador."
    else
        echo "[ERROR] Não foi possível criar a Pull Request."
        return 1
    fi
}


function display_help() {
    echo -e "\nFunções disponíveis no script:\n"
    
    echo -e "merge:\n"
    echo -e "  Realiza o push da branch atual para o repositório remoto e cria uma Pull Request (PR) no GitHub."
    echo -e "  Parâmetros:\n"
    echo -e "    -b : Define a branch de destino (padrão: sprint3-multiportal-feature)"
    echo -e "    -o : Código da COR, usado como identificador no título da PR"
    echo -e "    -d : Descrição detalhada da PR"
    echo -e "  Exemplo de uso:\n"
    echo -e "    merge -b branch-name -o COR-1234 -d \"Descrição da PR\"\n"

    echo -e "up:\n"
    echo -e "  Atualiza o corpo de uma PR existente, fazendo push da branch atual e editando a PR no GitHub."
    echo -e "  Parâmetros:\n"
    echo -e "    -b : Define a branch de destino (padrão: sprint3-multiportal-feature)"
    echo -e "  Exemplo de uso:\n"
    echo -e "    up -b branch-name\n"

    echo -e "commit:\n"
    echo -e "  Gera um commit com um tipo específico, usando um emoji correspondente ao tipo de mudança."
    echo -e "  Parâmetros:\n"
    echo -e "    -t : Tipo de commit (bug, feat, fix, etc.)"
    echo -e "    -m : Mensagem detalhada do commit"
    echo -e "  Exemplo de uso:\n"
    echo -e "    commit -t feat -m \"Adiciona nova funcionalidade\"\n"

    echo -e "sprint3:\n"
    echo -e "  Cria uma PR da branch sprint3-multiportal-feature para a branch sprint3 no GitHub."
    echo -e "  Sem parâmetros."
    echo -e "  Exemplo de uso:\n"
    echo -e "    sprint3\n"

    echo -e "staging:\n"
    echo -e "  Cria uma PR da branch sprint3-multiportal-feature para a branch staging no GitHub."
    echo -e "  Sem parâmetros."
    echo -e "  Exemplo de uso:\n"
    echo -e "    staging\n"
}

function cmd_menu() {
    # Função para obter opções de commit
    get_commit_types() {
        cat <<EOF
feat:✨ Nova funcionalidade
fix:🔧 Ajuste em funcionalidade
bug:🪲 Correção de bug
refactor:🔃 Refatoração de código
build:🛠 Alteração durante build
comment:💡 Comentário de código
delete:❌ Remoção de arquivo
deploy:🚀 Alteração no deploy
dependency:📦 Instalação de pacote
docs:📄 Alteração na documentação
downgrade:🔽 Rollback de versão
rename:🔤 Mudança de nome
revert:💥 Rollback de código
review:👌 Ajuste de Code Review
security:🔒 Ajuste de segurança
style:💄 Alteração de estilização
test:🧪 Teste automatizado
upgrade:🔼 Atualização de versão
wip:🚧 Mudança em desenvolvimento
EOF
    }

    # Função para obter opções dinâmicas para cada comando
    get_command_options() {
        local cmd=$1
        case $cmd in
            "commit")
                selected_type=$(get_commit_types | fzf \
                    --preview='echo {} | cut -d: -f1 | xargs -I{} bash -c "\
                        case {} in \
                            feat) echo \"Exemplo: Adição de funcionalidade de login\";; \
                            fix) echo \"Exemplo: Correção de cálculo no frontend\";; \
                            bug) echo \"Exemplo: Correção de um bug crítico no sistema\";; \
                            refactor) echo \"Exemplo: Melhoria na estrutura do código sem mudar funcionalidade\";; \
                            build) echo \"Exemplo: Ajustes na configuração de build\";; \
                            comment) echo \"Exemplo: Comentários explicativos para código\";; \
                            delete) echo \"Exemplo: Remoção de arquivos não usados\";; \
                            deploy) echo \"Exemplo: Atualização do pipeline de deploy\";; \
                            dependency) echo \"Exemplo: Adição de nova dependência ao projeto\";; \
                            docs) echo \"Exemplo: Atualização de documentação do README\";; \
                            downgrade) echo \"Exemplo: Reverter uma versão de dependência\";; \
                            rename) echo \"Exemplo: Renomear arquivo ou variável\";; \
                            revert) echo \"Exemplo: Reverter commit anterior\";; \
                            review) echo \"Exemplo: Ajustes pós code review\";; \
                            security) echo \"Exemplo: Correção de vulnerabilidade de segurança\";; \
                            style) echo \"Exemplo: Ajustes de espaçamento ou estilo de código\";; \
                            test) echo \"Exemplo: Adição de testes unitários\";; \
                            upgrade) echo \"Exemplo: Atualização de dependência para nova versão\";; \
                            wip) echo \"Exemplo: Trabalho em progresso para nova feature\";; \
                            *) echo \"Sem exemplo disponível\";; \
                        esac"' \
                    --preview-window=right:60% \
                    --height=70% \
                    --layout=reverse \
                    --info=hidden \
                    --header="Selecione o tipo de commit e veja um exemplo" | cut -d: -f1)

                if [[ -n "$selected_type" ]]; then
                    read -p "Mensagem do commit: " msg
                    echo "-t '$selected_type' -m '$msg'"
                fi
                ;;
            "merge")
                echo "Opções disponíveis para merge:" >&2
                git branch -r | grep -v '\->' | sed 's/origin\///' | fzf
                ;;
            "up")
                echo "Branches disponíveis:" >&2
                git branch -r | grep -v '\->' | sed 's/origin\///' | fzf
                ;;
        esac
    }

    # Menu principal de seleção de comandos
    selected_cmd=$(cat <<EOF | fzf --preview='display_help | grep -A5 "^'"$cmd"':"' \
        --preview-window=right:60% \
        --height=50% \
        --layout=reverse \
        --info=hidden \
        --header="Selecione um comando":
commit
merge
up
help
EOF
)
    
    if [[ -n "$selected_cmd" ]]; then
        # Se for help, chama direto
        if [[ "$selected_cmd" == "help" ]]; then
            display_help
            return
        fi

        # Obtém opções específicas do comando
        cmd_option=$(get_command_options "$selected_cmd")
        
        # Se o comando suporta opções, pede para selecionar
        if [[ -n "$cmd_option" ]]; then
            # Constrói o comando completo
            full_command="$selected_cmd $cmd_option"
            
            echo "Executando: $full_command"
            eval "$full_command"
        else
            echo "Executando: $selected_cmd"
            eval "$selected_cmd"
        fi
    fi
}

alias cmds='cmd_menu'
function help() {
    display_help
}

function start() {
    # Branchs default que usamos
    local default_branches=("main" "staging" "homolog" "sprint3")
    local sprint3_branches=($(git branch -r | grep 'origin/sprint3-' | sed 's/origin\///'))
    local all_base_branches=("${default_branches[@]}" "${sprint3_branches[@]}")
    
    local base_branch=""
    local new_branch=""
    local interactive_mode=false

    # Parse arguments
    TEMP=$(getopt -o "b:f:hi" --long "branch:,from:,help,interactive" -n 'start' -- "$@")
    
    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; return 1 ; fi
    
    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            -b|--branch)
                new_branch="$2"
                shift 2
                ;;
            -f|--from)
                # Trim whitespace from base_branch
                base_branch=$(echo "$2" | xargs)
                shift 2
                ;;
            -h|--help)
                echo "Uso: start [-b <nova_branch>] [-f <branch_base>] [-i]"
                echo "  -b, --branch  : Nome da nova branch"
                echo "  -f, --from    : Branch base (padrão: sprint3-multiportal-feature)"
                echo "  -i, --interactive : Modo interativo para seleção de branch"
                return 0
                ;;
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Erro interno"
                return 1
                ;;
        esac
    done

    # Interactive mode for branch selection if no base branch specified
    if [[ "$interactive_mode" == true || -z "$base_branch" ]]; then
        base_branch=$(printf '%s\n' "${all_base_branches[@]}" | fzf \
            --preview='git log -n 5 --pretty=format:"%h %s" origin/{}' \
            --preview-window=right:60% \
            --height=70% \
            --layout=reverse \
            --info=hidden \
            --header="Selecione a branch base" | xargs)
        
        # Exit if no branch selected
        if [[ -z "$base_branch" ]]; then
            echo "[ERROR] Nenhuma branch base selecionada"
            return 1
        fi
    fi

    # Validate base branch exists in remote
    if ! git ls-remote --exit-code --heads origin "$base_branch" > /dev/null 2>&1; then
        echo "[ERROR] Branch base '$base_branch' não existe no repositório remoto"
        echo "Branches disponíveis:"
        git branch -r | grep -v '\->'
        return 1
    fi

    # Default to sprint3-multiportal-feature if no base branch specified
    base_branch=${base_branch:-"sprint3-multiportal-feature"}

    # Interactive or manual branch name input
    if [[ -z "$new_branch" ]]; then
        read -p "Nome da nova branch (exemplo: sprint3-feature-name): " new_branch
    fi

    # Validate branch name
    if [[ -z "$new_branch" ]]; then
        echo "[ERROR] Nome da branch não pode ser vazio"
        return 1
    fi

    # Prefix branch name with sprint3- if not already prefixed and doesn't start with COR-
    if [[ ! "$new_branch" =~ ^sprint3- && ! "$new_branch" =~ ^COR- ]]; then
        new_branch="${new_branch}"
    fi

    # Create and checkout the new branch
    git fetch origin "$base_branch"
    git checkout -b "$new_branch" "origin/$base_branch"
    
    if [[ $? -eq 0 ]]; then
        echo "Branch '$new_branch' criada a partir de '$base_branch'"
        return 0
    else
        echo "[ERROR] Não foi possível criar a branch"
        return 1
    fi
}

function generate_pr_body() {
    echo "Commits:"
    git log --pretty=format:" - %s" origin/${branch}..HEAD
}

function mer() {
    local branch=""
    local identifier=""
    local identifier_type=""
    local desc=""
    local pr_title=""
    local pr_body=""

    # Seleção do branch de destino
    branch=$(git branch -r | grep -v '\->' | sed 's/origin\///' | fzf \
        --preview='git log -n 5 --pretty=format:"%h %s" origin/{}' \
        --preview-window=right:60% \
        --height=70% \
        --layout=reverse \
        --info=hidden \
        --header="Selecione a branch de destino")

    branch=$(echo "$branch" | xargs)  # Remover espaços extras

    if [[ -z "$branch" || "$branch" =~ [[:space:]] ]]; then
        echo "[ERROR] O nome do branch é inválido: '$branch'"
        return 1
    fi

    # Seleção do tipo de identificador
    identifier_type=$(echo -e "COR\nIMP\nConflitos\nMigration" | fzf \
        --preview='case {} in 
            COR) echo "Correção de Requisito - Obrigatório número" ;;
            IMP) echo "Impedimento - Obrigatório número" ;;
            Conflitos) echo "Resolução de Conflitos - Opcional número" ;;
            Migration) echo "Migration - Opcional número" ;;
        esac' \
        --preview-window=right:60% \
        --height=50% \
        --layout=reverse \
        --info=hidden \
        --header="Selecione o tipo de identificador")

    if [[ -z "$identifier_type" ]]; then
        echo "[ERROR] Nenhum tipo de identificador selecionado."
        return 1
    fi

    # Entrada do número do identificador
    case "$identifier_type" in
        COR|IMP)
            while true; do
                read -p "Digite o número do ${identifier_type} (ex: 1234, obrigatório): " identifier
                if [[ "$identifier" =~ ^[0-9]+$ ]]; then
                    break
                else
                    echo "[ERROR] Número inválido. Digite apenas números."
                fi
            done
            ;;
        Conflitos|Migration)
            read -p "Digite o número opcional (ou deixe em branco): " identifier
            ;;
    esac

    # Entrada da descrição
    while true; do
        read -p "Descrição da Pull Request: " desc
        if [[ -n "$desc" ]]; then
            break
        else
            echo "[ERROR] A descrição não pode ser vazia."
        fi
    done

    # Construir título da PR
    if [[ -n "$identifier" ]]; then
        pr_title="[${identifier_type}-${identifier}] ${desc}"
    else
        pr_title="[${identifier_type}] ${desc}"
    fi

    # Garantir commits no branch atual
    git fetch origin "${branch}"
    if ! git log "${branch}..HEAD" --oneline | grep .; then
        echo "[ERROR] Não há commits entre ${branch} e o branch atual."
        return 1
    fi

    # Fazer push para o branch remoto
    echo "Executando: git push origin HEAD"
    git push origin HEAD
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Não foi possível fazer o push para a branch."
        return 1
    fi

    # Gerar corpo da PR
    pr_body="Commits: \n \n $(git log --oneline "${branch}..HEAD" | sed 's/^/- /')"

    # Criar PR
    # echo "Executando: gh pr create --base ${branch} --title '${pr_title}' --body '${pr_body}'"
    pr_url=$(gh pr create --base "${branch}" --title "${pr_title}" --body "${pr_body}")
    if [[ $? -eq 0 ]]; then
        echo "Pull Request criada com sucesso: ${pr_url}"
        
        pr_number=$(echo "$pr_url" | grep -oP "(?<=/pull/)\d+")
        
        # Send Slack notification
        webhook_response=$(go run ~/scripts_ubuntu/utils/send_slack_message.go "${pr_url}" "${pr_title}" "${pr_number}")
        
        echo "$webhook_response"
    else
        echo "[ERROR] Não foi possível criar a Pull Request."
    fi
}


function merge() {
    # Default values
    local branch="sprint3-multiportal-feature"
    local identifier=""
    local identifier_type=""
    local desc=""
    local error_message=""

    # Parse arguments
    TEMP=$(getopt -o "b:i:n:d:h" --long "branch:,type:,number:,description:,help" -n 'merge' -- "$@")
    
    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; return 1 ; fi
    
    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            -i|--type)
                identifier_type="$2"
                shift 2
                ;;
            -n|--number)
                identifier="$2"
                shift 2
                ;;
            -d|--description)
                desc="$2"
                shift 2
                ;;
            -h|--help)
                display_help
                return 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Erro interno"
                return 1
                ;;
        esac
    done

    # Validation logic
    if [[ "$identifier_type" == "COR" || "$identifier_type" == "IMP" ]]; then
        if [[ ! "$identifier" =~ ^[0-9]+$ ]]; then
            error_message+="[ERROR] O número do ${identifier_type} é obrigatório e deve ser numérico\n"
        fi
    elif [[ "$identifier_type" == "Conflitos" || "$identifier_type" == "Migration" ]]; then
        # These types can have an optional number
        if [[ -n "$identifier" && ! "$identifier" =~ ^[0-9]+$ ]]; then
            error_message+="[ERROR] O número deve ser numérico\n"
        fi
    fi

    # Mandatory description
    if [[ $desc == "" ]]; then 
        error_message+="[ERROR] Nenhuma descrição informada\n"
    fi 

    # Check if all required parameters are provided
    if [[ -z "$identifier_type" ]]; then
        error_message+="[ERROR] Tipo de identificador não informado\n"
    fi

    if [[ -n $error_message ]]; then
        echo -e "$error_message"
        return 1
    fi

    # Construct PR title based on type
    if [[ -n "$identifier" ]]; then
        pr_title="[${identifier_type}-${identifier}] ${desc}"
    else
        pr_title="[${identifier_type}] ${desc}"
    fi

    # Push current branch
    echo "Executando: git push origin HEAD"
    git push origin HEAD
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Não foi possível fazer o push para a branch."
        return 1
    fi

    # Generate PR body
    pr_body=$(generate_pr_body)

    # Create PR
    echo "Executando: gh pr create --base ${branch} --title '${pr_title}' --body '${pr_body}'"
    pr_url=$(gh pr create --base "${branch}" --title "${pr_title}" --body "${pr_body}")
    
    if [[ $? -eq 0 ]]; then
        echo "Pull Request criada com sucesso: ${pr_url}"
        
        pr_number=$(echo "$pr_url" | grep -oP "(?<=/pull/)\d+")
        
        # Send Slack notification
        webhook_response=$(go run ~/scripts_ubuntu/utils/send_slack_message.go "${pr_url}" "${pr_title}" "${pr_number}")
        
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
        echo "[ERROR] Nenhuma mensagem de commit especificada"
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

function gem() {
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
            "start")
                base_branch=$(git branch -r | grep -v '\->' | sed 's/origin\///' | fzf)
                
                if [[ -z "$base_branch" ]]; then
                    echo "[ERROR] Nenhuma branch base selecionada. Operação cancelada."
                    return 1
                fi

                # Sempre solicitar o nome da nova branch
                read -p "Nome da nova branch (exemplo: sprint3-feature-name): " branch_name
                
                # Validar se o nome da branch foi fornecido
                if [[ -z "$branch_name" ]]; then
                    echo "[ERROR] O nome da branch não pode ser vazio."
                    return 1
                fi

                echo "-f '$base_branch' -b '$branch_name'"
                ;;
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
start
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


alias cmds='gem'


#    ascii_art=$(cat <<'EOF'
#  ______                              _      
#  |  ____|                            | |     
#  | |__    _ __ ___    ___  __ _  ___ | |__   
#  |  __|  | '_ ` _ \  / __|/ _` |/ __|| '_ \  
#  | |____ | | | | | || (__| (_| |\__ \| | | | 
#  |______||_| |_| |_| \___|\__,_||___/|_| |_| 
#   / ____|            (_)                     
#  | |      ___   _ __  _  _ __    __ _   __ _ 
#  | |     / _ \ | '__|| || '_ \  / _` | / _` |
#  | |____| (_) || |   | || | | || (_| || (_| |
#   \_____|\___/ |_|   |_||_| |_| \__, | \__,_|
#                                  __/ |       
#                                 |___/        
# EOF
# )


# function mergee() {
#     # Default values
#     branch="sprint3-multiportal-feature"
#     identifier=""
#     identifier_type=""
#     desc=""
#     error_message=""
#     interactive_mode=false

#     # Parse arguments
#     TEMP=$(getopt -o "b:i:t:d:hi" --long "branch:,identifier:,type:,description:,help,interactive" -n 'merge' -- "$@")
    
#     if [ $? != 0 ] ; then echo "Terminating..." >&2 ; return 1 ; fi
    
#     eval set -- "$TEMP"
    
#     while true ; do
#         case "$1" in
#             -b|--branch)
#                 branch="$2"
#                 shift 2
#                 ;;
#             -i|--identifier)
#                 identifier="$2"
#                 shift 2
#                 ;;
#             -t|--type)
#                 identifier_type="$2"
#                 shift 2
#                 ;;
#             -d|--description)
#                 desc="$2"
#                 shift 2
#                 ;;
#             -h|--help)
#                 display_help
#                 return 0
#                 ;;
#             -i|--interactive)
#                 interactive_mode=true
#                 shift
#                 ;;
#             --)
#                 shift
#                 break
#                 ;;
#             *)
#                 echo "Erro interno"
#                 return 1
#                 ;;
#         esac
#     done

#     # Interactive mode selection
#     if [[ "$interactive_mode" == true || -z "$branch" || -z "$identifier_type" || -z "$identifier" || -z "$desc" ]]; then
#         # Select branch
#         branch=$(git branch -r | grep -v '\->' | sed 's/origin\///' | fzf \
#             --preview='git log -n 5 --pretty=format:"%h %s" origin/{}' \
#             --preview-window=right:60% \
#             --height=70% \
#             --layout=reverse \
#             --info=hidden \
#             --header="Selecione a branch de destino")

#         # Select identifier type
#         identifier_type=$(echo -e "COR\nIMP\nCONFLITS" | fzf \
#             --preview='case {} in 
#                 COR) echo "Correção de Requisito" ;;
#                 IMP) echo "Impedimento" ;;
#                 CONFLITS) echo "Resolução de Conflitos" ;;
#             esac' \
#             --preview-window=right:60% \
#             --height=50% \
#             --layout=reverse \
#             --info=hidden \
#             --header="Selecione o tipo de identificador")

#         # Input identifier based on type
#         case "$identifier_type" in
#             COR|IMP)
#                 read -p "Digite o número do ${identifier_type} (ex: ${identifier_type}-1234): " identifier
#                 ;;
#             CONFLITS)
#                 identifier="" # No identifier for CONFLITS
#                 ;;
#         esac

#         # Input description
#         read -p "Descrição da Pull Request: " desc
#     fi

#     # Validate identifier and type
#     if [[ "$identifier_type" == "COR" && ! "$identifier" =~ ^COR-([0-9]+(-[0-9]+)*)$ ]]; then
#         error_message+="[ERROR] O número do COR (COR-XXXX) é obrigatório e deve ser numérico\n"
#     elif [[ "$identifier_type" == "IMP" && ! "$identifier" =~ ^IMP-([0-9]+(-[0-9]+)*)$ ]]; then
#         error_message+="[ERROR] O número do IMPEDIMENTO (IMP-XXXX) é obrigatório e deve ser numérico\n"
#     elif [[ "$identifier_type" == "CONFLITS" && "$identifier" != "" ]]; then
#         error_message+="[ERROR] Para CONFLITS não deve ser fornecido número\n"
#     fi

#     if [[ $desc == "" ]]; then 
#         error_message+="[ERROR] Nenhuma descrição informada\n"
#     fi 

#     if [[ -n $error_message ]]; then
#         echo -e "$error_message"
#         return 1
#     fi

#     # Push current branch
#     echo "Executando: git push origin HEAD"
#     git push origin HEAD
#     if [[ $? -ne 0 ]]; then
#         echo "[ERROR] Não foi possível fazer o push para a branch."
#         return 1
#     fi

#     # Generate PR body
#     pr_body=$(generate_pr_body)

#     # Create PR
#     echo "Executando: gh pr create --base ${branch} --title [${identifier_type}-${identifier}] ${desc} --body ${pr_body}"
#     pr_url=$(gh pr create --base "${branch}" --title "[${identifier_type}-${identifier}] ${desc}" --body "${pr_body}")
    
#     if [[ $? -eq 0 ]]; then
#         echo "Pull Request criada com sucesso: ${pr_url}"
        
#         pr_title="[${identifier_type}-${identifier}] ${desc}"
#         pr_number=$(echo "$pr_url" | grep -oP "(?<=/pull/)\d+")
        
#         # Send Slack notification
#         webhook_response=$(go run ~/scripts_ubuntu/utils/send_slack_message.go "${pr_url}" "${pr_title}" "${pr_number}")
        
#         echo "$webhook_response"
#     else
#         echo "[ERROR] Não foi possível criar a Pull Request."
#     fi
# }
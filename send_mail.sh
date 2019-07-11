#!/usr/bin/env python3
import postgresql
import smtplib
import email.message
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import sys

if len(sys.argv) != 4:
	print('send_mail.sh connstr taigaip smtpurl smtpport smtpuser smtppassword mailfrom')

db = postgresql.open(sys.argv[0])
users = db.query('SELECT id, full_name, email FROM "users_user" WHERE COALESCE("users_user"."is_active",False) = True')
tasks = db.query('''
SELECT
        tab."user_id",
        '<tr><td>'||tab."type"||'</td><td><span style="color:'||tab."priority_color"||'">'||tab."priority_name"||'</span></td><td>'||COALESCE(to_char(tab."duedate",'YYYY-MM-DD'),'-')||'</td><td>'||tab."status"||'</td><td><a href="'||tab."url"||'">'||tab."task"||'</a></td></tr>' as "html_row"
FROM
(SELECT
        COALESCE(u."user_id", us."assigned_to_id") as "user_id",
        'Проект' as "type",
        proj."name" as "project",
        us."subject" as "task",
        'https://'||sys.argv[1]||'/project/'||proj."slug"||'/us/'||us."ref" as "url",
        us."due_date" as "duedate",
        s."name" as "status",
        (SELECT "projects_priority"."name" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_name",
        (SELECT "projects_priority"."color" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_color",
        (SELECT "projects_priority"."order" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_order"
FROM "userstories_userstory" as us
INNER JOIN "projects_project" as proj ON us."project_id" = proj."id"
INNER JOIN "projects_userstorystatus" as s ON us."status_id" = s."id" AND COALESCE(s."is_closed",False)=False
LEFT JOIN "userstories_userstory_assigned_users" as u ON u."userstory_id" = us."id"
UNION ALL
SELECT
        t."assigned_to_id" as "user_id",
        'Задача проекта' as "type",
        proj."name" as "project",
        t."subject" as "task",
        'https://'||sys.argv[1]||'/project/'||proj."slug"||'/task/'||t."ref" as "url",
        t."due_date" as "duedate",
        s."name" as "status",
        (SELECT "projects_priority"."name" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_name",
        (SELECT "projects_priority"."color" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_color",
        (SELECT "projects_priority"."order" FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id" AND "projects_priority"."order" >=
                (SELECT ROUND(COUNT(*)/2.0) FROM "projects_priority" WHERE proj."id" = "projects_priority"."project_id") ORDER BY "projects_priority"."order" ASC LIMIT 1) as "priority_order"
FROM "userstories_userstory" as us
INNER JOIN "projects_project" as proj ON us."project_id" = proj."id"
RIGHT JOIN "tasks_task" as t ON us."id" = t."user_story_id"
INNER JOIN "projects_taskstatus" as s ON t."status_id" = s."id" AND COALESCE(s."is_closed",False)=False
UNION ALL
SELECT
        i."assigned_to_id" as "user_id",
        'Задача' as "type",
        proj."name" as "project",
        i."subject" as "task",
        'https://'||sys.argv[1]||'/project/'||proj."slug"||'/issue/'||i."ref" as "url",
        i."due_date" as "duedate",
        s."name" as "status",
        p.name as "priority_name",
        p.color as "priority_color",
        p.order as "priority_order"
FROM "issues_issue" as i
INNER JOIN "projects_project" as proj ON i."project_id" = proj."id"
INNER JOIN "projects_issuestatus" as s ON i."status_id" = s."id" AND COALESCE(s."is_closed",False)=False
LEFT JOIN "projects_priority" as p ON p."project_id" = proj."id" AND i."priority_id" = p."id" ) as tab
ORDER BY tab."user_id" ASC, tab."duedate" ASC, tab."priority_order" DESC, tab."status" ASC, tab."task" ASC''')

msg_body = ''

for user in users:
    if user["id"] != 6:
        continue
    mytasks = (task["html_row"] for task in tasks if task['user_id'] == user["id"])
    msg_body = '<!DOCTYPE html><html lang=ru><head><meta charset=utf-8><style>table { font-family: "Lucida Sans Unicode", "Lucida Grande", Sans-Serif; border-collapse: collapse; color: #686461; } caption { padding: 10px; color: white; background: #8FD4C1; font-size: 18px; text-align: left; font-weight: bold; } th { border-bottom: 3px solid #B9B29F; padding: 10px; text-align: left; } td { padding: 10px; } tr:nth-child(odd) { background: white; } tr:nth-child(even) { background: #E8E6D1; }</style></head><body><h1>Доброе утро, ' + user["full_name"] + '!</h1><table width="100%"><caption>Ваши актуальные задачи:</caption><tr><th>Тип</th><th>Приоритет</th><th>Срок</th><th>Статус</th><th>Наименование</th></tr>'
    for row in mytasks:
        msg_body += row
    msg_body += "</table></body></html>"
    msg = MIMEMultipart()
    msg['Subject'] = 'Список текущих задач'
    msg['From'] = sys.argv[6]
    msg['To'] = user["email"]
    body = MIMEText(msg_body, 'html')
    msg.attach(body)
    s = smtplib.SMTP(sys.argv[2],sys.argv[3])
    s.starttls()
    s.login(sys.argv[4],sys.argv[5])
    s.sendmail(msg['From'], msg['To'], msg.as_string())
    s.quit()
